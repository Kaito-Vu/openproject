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

module Screens
  # Two tiers, as designed in spec section 4:
  #   1. Cheap checks that can block a save: an in-use create screen must place subject.
  #   2. Checks that depend on F02 or on the projects using a scheme never block; they are warnings.
  class CoverageValidation
    Result = Data.define(:errors, :warnings)

    class << self
      def screen(screen)
        return Result.new(errors: [], warnings: []) unless screen.create?

        live_items = screen.items.reject(&:marked_for_destruction?)
        subject_visible = live_items.any? { |item| item.field_key == "subject" && item.visible }
        if screen.in_use?
          Result.new(errors: subject_visible ? [] : [:required_not_placed], warnings: [])
        else
          warnings = []
          warnings << :empty_create_screen if live_items.empty?
          warnings << :required_not_placed unless subject_visible
          Result.new(errors: [], warnings:)
        end
      end

      # Tier 1.2: placing a create screen on a scheme row requires the type's required fields to be
      # placed, and none of them to be hidden by F02 (hidden_and_required). It only covers the row's
      # own type and is capped; above the cap it degrades to a warning instead of blocking. Pass
      # project_ids to check a project that is about to be assigned the scheme.
      def scheme_item(item, project_ids: nil)
        return Result.new(errors: [], warnings: []) if item.create_screen.nil? || item.marked_for_destruction?

        required = RequiredSet.for_scheme_type(item.scheme, item.type, project_ids:)
        return Result.new(errors: [], warnings: [:skipped_due_to_scale]) if required == :skipped

        hidden = RequiredSet.hidden_for_scheme_type(required.keys, item.type)
        errors = required.flat_map do |project_id, keys|
          keys.filter_map do |key|
            code = if hidden[project_id]&.include?(key)
                     :hidden_and_required
                   elsif !placed_visible?(item.create_screen, key)
                     :required_not_placed
                   end
            { code:, field: key, type_id: item.type_id, project_id: } if code
          end
        end
        Result.new(errors: errors.first(10), warnings: errors.size > 10 ? [:more_required_not_placed] : [])
      end

      # Non-blocking warnings for editor saves, e.g. [{ code: "hidden_but_placed", fields: ["status"] }].
      def warnings_for(screen)
        warnings = screen(screen).warnings.map { |code| { code: code.to_s } }
        hidden = hidden_but_placed(screen)
        warnings << { code: "hidden_but_placed", fields: hidden } if hidden.any?
        warnings
      end

      private

      def placed_visible?(screen, key)
        screen.items.any? { |item| item.field_key == key && item.visible }
      end

      # Placed fields that F02 hides for a (project, type) using this screen. Skipped above the
      # project cap, like the other checks that fan out over projects.
      def hidden_but_placed(screen)
        return [] unless RequiredSet.field_rules?

        Resolver.fail_open("hidden_but_placed check", [], screen_id: screen.id) do
          rows = screen.scheme_items.pluck(:scheme_id, :type_id)
          next [] if rows.empty?

          projects = ProjectScreenScheme.where(scheme_id: rows.map(&:first).uniq).pluck(:scheme_id, :project_id)
          project_ids = projects.map(&:last).uniq
          next [] if project_ids.empty? || project_ids.size > RequiredSet::MAX_PROJECTS

          type_ids = rows.map(&:last).uniq
          placed = screen.items.select(&:visible).map(&:field_key)
          config = ::FieldRules::Resolver.for_many(project_ids, type_ids)
          config.values.flat_map { |rules| rules.select(&:hidden).map(&:key) }.uniq & placed
        end
      end
    end
  end
end
