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

module FieldRules
  module Resolver
    CACHE_KEY = :field_rules_by_project_and_type

    module_function

    def for(project, type)
      project_id = id_of(project)
      type_id = id_of(type)
      return EffectiveConfiguration.empty if project_id.nil? || type_id.nil?

      OpenProject::FieldRules.fail_open("resolving rules", EffectiveConfiguration.empty, project_id:, type_id:) do
        cache = cache_store
        cache[:pairs].fetch([project_id, type_id]) do
          # One query loads every type of the project, so lists over many work packages stay at one query per project.
          for_many([project_id]) unless cache[:loaded_projects].include?(project_id)
          cache[:pairs][[project_id, type_id]] ||= EffectiveConfiguration.empty
        end
      end
    end

    # Preloads many (project, type) pairs with a single query to avoid N+1 in lists, exports and bulk operations.
    # Always returns a Hash{[project_id, type_id] => EffectiveConfiguration}. Without type_ids every type of the
    # projects is loaded (and the projects are marked as fully cached) and only configured pairs are in the Hash.
    def for_many(project_ids, type_ids = nil)
      project_ids = Array(project_ids).compact.uniq
      cache = cache_store
      return preload_projects(project_ids, cache) if type_ids.nil?

      type_ids = Array(type_ids).compact.uniq
      all_pairs = project_ids.product(type_ids)
      missing = all_pairs.reject { |pair| cache[:pairs].key?(pair) || cache[:loaded_projects].include?(pair.first) }
      if missing.any?
        grouped = load_rules(project_ids, type_ids).group_by do |rule|
          [rule.attributes["fr_project_id"], rule.attributes["fr_type_id"]]
        end
        missing.each { |pair| cache[:pairs][pair] = EffectiveConfiguration.from_rules(grouped.fetch(pair, [])) }
      end
      all_pairs.to_h { |pair| [pair, cache[:pairs][pair] || EffectiveConfiguration.empty] }
    end

    def editable?(project, type, field_key)
      self.for(project, type).editable?(field_key)
    end

    def reset_cache
      RequestStore.store.delete(CACHE_KEY)
    end

    def system_actor?(user)
      user.is_a?(SystemUser)
    end

    def cache_store
      RequestStore.store[CACHE_KEY] ||= { pairs: {}, loaded_projects: Set.new }
    end

    def preload_projects(project_ids, cache)
      pending = project_ids.reject { |project_id| cache[:loaded_projects].include?(project_id) }
      if pending.any?
        load_rules(pending, nil).group_by { |rule| [rule.attributes["fr_project_id"], rule.attributes["fr_type_id"]] }
                                .each { |pair, rules| cache[:pairs][pair] = EffectiveConfiguration.from_rules(rules) }
        cache[:loaded_projects].merge(pending)
      end
      cache[:pairs].select { |(project_id, _type_id), _config| project_ids.include?(project_id) }
    end

    def load_rules(project_ids, type_ids)
      scope = FieldRule
        .joins(rule_set: { scheme_items: { scheme: :project_assignments } })
        .where(field_rule_sets: { active: true },
               field_rule_schemes: { active: true },
               project_field_rule_schemes: { project_id: project_ids })
      scope = scope.where(field_rule_scheme_items: { type_id: type_ids }) if type_ids
      scope
        .select("field_rules.*",
                "project_field_rule_schemes.project_id AS fr_project_id",
                "field_rule_scheme_items.type_id AS fr_type_id")
        .order(:position, :id)
        .to_a
    end

    def id_of(record)
      record.respond_to?(:id) ? record.id : record
    end
  end
end
