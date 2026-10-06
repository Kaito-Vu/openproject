#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++
# frozen_string_literal: true

require "set"

module Screens
  # The single source of truth for the effective layout of a (project, type, context). It merges
  # the screen configuration with the field rules (F02) and never raises into its callers: any
  # internal error falls back to the native layout.
  module Resolver
    CACHE_KEY = :screens_resolved
    CONTEXTS = %i[create edit view transition].freeze
    FALLBACKS = {
      create: %i[create],
      edit: %i[edit],
      view: %i[view edit],
      transition: %i[transition]
    }.freeze
    MAX_FOR_MANY = 500

    @raise_on_error = false

    class << self
      attr_accessor :raise_on_error
    end

    module_function

    def for(project, type, context)
      context = normalize_context(context)
      project_id = id_of(project)
      type_id = id_of(type)
      return native(:no_scheme, context) if project_id.nil? || type_id.nil?

      cache = RequestStore.store[CACHE_KEY] ||= {}
      key = [project_id, type_id, context]
      cache.fetch(key) { cache[key] = resolve(project, type, context) }
    rescue ArgumentError
      raise
    rescue StandardError => e
      raise if raise_on_error

      report(e, project, type, context)
      native(:error, context, error: true)
    end

    # Resolves up to 500 (project, type, context) keys. Returns a hash keyed by those triples.
    def for_many(project_ids:, type_ids:, contexts:)
      project_ids = Array(project_ids).compact.uniq
      type_ids = Array(type_ids).compact.uniq
      contexts = Array(contexts).map { |context| normalize_context(context) }.uniq
      pairs = project_ids.product(type_ids, contexts)
      raise ArgumentError, "at most #{MAX_FOR_MANY} keys are supported" if pairs.size > MAX_FOR_MANY

      projects = Project.where(id: project_ids).index_by(&:id)
      types = Type.where(id: type_ids).index_by(&:id)
      preloaded = preload_many(projects.keys, types.keys)
      pairs.index_with do |project_id, type_id, context|
        project = projects[project_id]
        type = types[type_id]
        if project.nil? || type.nil?
          native(:no_scheme, context)
        else
          resolve_guarded(project, type, context, preloaded)
        end
      end
    end

    # A compact type x context grid for project settings, resolved from a single scheme load and
    # without loading sections or items.
    def matrix(project)
      project_id = id_of(project)
      return {} if project_id.nil?

      type_ids = project.enabled_types.order(:position).pluck(:id)
      assignment = project_assignment(project_id)
      reason = assignment.nil? ? "no_scheme" : "scheme_inactive"
      if assignment.nil? || !assignment.scheme_active?
        return empty_matrix(type_ids, reason)
      end

      items = ScreenSchemeItem.where(scheme_id: assignment.scheme_id).to_a
      screens = screens_for(items)
      by_type = items.index_by(&:type_id)

      type_ids.to_h do |type_id|
        item = by_type[type_id]
        if item.nil?
          [type_id, grid_row(nil, "type_not_in_scheme", {})]
        else
          row = ScreenScheme::CONTEXTS.to_h do |context|
            screen, skipped = choose_screen(item, context, screens)
            [context, screen ? screen_cell(screen, skipped) : native_cell("no_usable_screen", skipped)]
          end
          [type_id, row]
        end
      end
    end

    def reset_cache
      RequestStore.store.delete(CACHE_KEY)
      ::FieldRules::Resolver.reset_cache if RequiredSet.field_rules?
    end

    def normalize_context(context)
      normalized = context.to_sym
      raise ArgumentError, "invalid screen context #{context.inspect}" unless CONTEXTS.include?(normalized)

      normalized
    end

    def id_of(record)
      record.respond_to?(:id) ? record.id : record
    end

    # for_many variant of the error handling in .for: any internal error falls back to native.
    def resolve_guarded(project, type, context, preloaded)
      resolve(project, type, context, preloaded)
    rescue StandardError => e
      raise if raise_on_error

      report(e, project, type, context)
      native(:error, context, error: true)
    end

    # Loads everything for_many needs with a constant number of queries: project/type links,
    # scheme assignments, scheme items and the used screens with their sections and items.
    def preload_many(project_ids, type_ids)
      links = ProjectType.where(project_id: project_ids, type_id: type_ids).pluck(:project_id, :type_id).to_set
      assignments = ProjectScreenScheme
                    .joins(:scheme)
                    .where(project_id: project_ids)
                    .select("project_screen_schemes.*, screen_schemes.active AS scheme_active")
                    .index_by(&:project_id)
      items = ScreenSchemeItem.where(scheme_id: assignments.values.map(&:scheme_id).uniq, type_id: type_ids)
                              .index_by { |item| [item.scheme_id, item.type_id] }
      screen_ids = items.values.flat_map { |item| ScreenScheme::SLOTS.values.map { |slot| item.public_send(:"#{slot}_id") } }
      screens = Screen.includes(sections: :items).where(id: screen_ids.compact.uniq).index_by(&:id)
      { links:, assignments:, items:, screens:,
        field_keys: screens.values.flat_map { |screen| screen.sections.flat_map { |section| section.items.map(&:field_key) } }.uniq,
        availability: {}, required: {} }
    end

    def resolve(project, type, context, preloaded = nil)
      in_project = preloaded ? preloaded[:links].include?([project.id, type.id]) : type_in_project?(project, type)
      return native(:type_not_in_project, context) unless in_project

      assignment = preloaded ? preloaded[:assignments][project.id] : project_assignment(project.id)
      return native(:no_scheme, context) if assignment.nil?
      return native(:scheme_inactive, context) unless assignment.scheme_active?

      item = if preloaded
               preloaded[:items][[assignment.scheme_id, type.id]]
             else
               ScreenSchemeItem.where(scheme_id: assignment.scheme_id, type_id: type.id).first
             end
      return native(:type_not_in_scheme, context) if item.nil?

      screen, skipped = choose_screen(item, context, preloaded&.fetch(:screens))
      return native(:no_usable_screen, context, skipped:) if screen.nil?

      loaded = preloaded ? screen : Screen.includes(sections: :items).find(screen.id)
      build_screen(project, type, context, loaded, skipped, preloaded)
    end

    def type_in_project?(project, type)
      ProjectType.exists?(project_id: project.id, type_id: type.id)
    end

    def project_assignment(project_id)
      ProjectScreenScheme
        .joins(:scheme)
        .where(project_id:)
        .select("project_screen_schemes.*, screen_schemes.active AS scheme_active")
        .first
    end

    def screens_for(items)
      ids = items.flat_map do |item|
        ScreenScheme::SLOTS.values.map { |slot| item.public_send(:"#{slot}_id") }
      end.compact.uniq
      Screen.where(id: ids).index_by(&:id)
    end

    def choose_screen(item, context, screens = nil)
      skipped = []
      FALLBACKS.fetch(context).each do |slot|
        screen = slot_screen(item, slot, screens)
        next if screen.nil?
        next skipped << { slot: slot, screenId: screen.id, reason: "inactive" } unless screen.active?
        next skipped << { slot: slot, screenId: screen.id, reason: "type_mismatch" } unless screen.screen_type == slot.to_s

        return [screen, skipped]
      end
      [nil, skipped]
    end

    def slot_screen(item, slot, screens)
      column = ScreenScheme::SLOTS.fetch(slot)
      if screens
        screens[item.public_send(:"#{column}_id")]
      else
        item.public_send(column)
      end
    end

    def build_screen(project, type, context, screen, skipped, preloaded = nil)
      field_rules = field_rules_for(project, type)
      all_items = screen.sections.flat_map(&:items)

      available = if preloaded
                    # once per (project, type) for the keys of every preloaded screen
                    preloaded[:availability][[project.id, type.id]] ||=
                      ::Screens::Fields.availability(preloaded[:field_keys], project:, type:)
                  else
                    ::Screens::Fields.availability(all_items.map(&:field_key), project:, type:)
                  end
      unavailable = all_items.reject { |item| available[item.field_key] }.map(&:field_key).uniq
      hidden = all_items.select { |item| field_rules&.hidden?(item.field_key) }.map(&:field_key).uniq
      not_visible = all_items.reject(&:visible).map(&:field_key).uniq
      placed = all_items.select(&:visible).map(&:field_key).to_set
      required = if context != :create
                   []
                 elsif preloaded
                   preloaded[:required][[project.id, type.id]] ||= RequiredSet.for(project, type)
                 else
                   RequiredSet.for(project, type)
                 end
      required_not_placed = required.reject { |key| placed.include?(key) }

      sections = screen.sections.map do |section|
        fields = section.items
                        .sort_by { |item| [item.position.to_i, item.id.to_i] }
                        .select { |item| item.visible && available[item.field_key] && !field_rules&.hidden?(item.field_key) }
                        .map { |item| build_field(item, field_rules) }
        { id: section.id, name: section.name, position: section.position, fields: fields }
      end

      ResolvedScreen.new(
        source: :screen,
        reason: nil,
        context: context.to_s,
        screen:,
        sections:,
        state_source: field_rules ? "field_rules" : nil,
        diagnostics: {
          unavailable:,
          hidden_but_placed: hidden,
          required_not_placed:,
          not_visible:,
          skipped:,
          empty_create_screen: screen.create? && all_items.empty?,
          error: false
        }
      )
    end

    def build_field(item, field_rules)
      state = if field_rules
                { required: field_rules.required?(item.field_key),
                  readOnly: field_rules.read_only?(item.field_key),
                  defaultValue: field_rules[item.field_key]&.default_value }
              end
      { key: item.field_key,
        label: ::Screens::Fields.label(item.field_key),
        position: item.position,
        width: item.width,
        state: state }
    end

    def field_rules_for(project, type)
      return nil unless RequiredSet.field_rules?

      fail_open("field rules lookup", nil, project_id: id_of(project), type_id: id_of(type)) do
        ::FieldRules::Resolver.for(project, type)
      end
    end

    def native(reason, context, skipped: [], error: false)
      ResolvedScreen.new(
        source: :native,
        reason: reason.to_s,
        context: context.to_s,
        screen: nil,
        sections: [],
        state_source: nil,
        diagnostics: {
          unavailable: [],
          hidden_but_placed: [],
          required_not_placed: [],
          not_visible: [],
          skipped:,
          empty_create_screen: false,
          error:
        }
      )
    end

    # Runs the block; on StandardError logs and reports it (never silent) and returns fallback.
    def fail_open(where, fallback, **context)
      yield
    rescue StandardError => e
      OpenProject.logger.error("[screens] #{where} failed, failing open: #{e.class}: #{e.message}")
      begin
        Rails.error.report(e, handled: true, context: context.merge(where:))
      rescue StandardError
        nil
      end
      fallback
    end

    def report(error, project, type, context)
      OpenProject.logger.error(
        "[screens] resolving layout failed, using native layout: #{error.class}: #{error.message}"
      )
      Rails.error.report(error, handled: true,
                                context: { project_id: id_of(project), type_id: id_of(type), context: })
    rescue StandardError
      nil
    end

    def empty_matrix(type_ids, reason)
      type_ids.to_h { |type_id| [type_id, grid_row(nil, reason, {})] }
    end

    def grid_row(_screen, reason, contexts)
      ScreenScheme::CONTEXTS.to_h do |context|
        cell = contexts[context]
        [context, cell || native_cell(reason, [])]
      end
    end

    def screen_cell(screen, skipped)
      { source: "screen", reason: nil, screen_id: screen.id, screen_name: screen.name, skipped: }
    end

    def native_cell(reason, skipped)
      { source: "native", reason: reason.to_s, screen_id: nil, screen_name: nil, skipped: }
    end
  end
end
