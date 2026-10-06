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

module OpenProject::FieldRules
  module SchemaPatch
    def to_json(*)
      json = super
      configuration = field_rules_schema_configuration
      return json if configuration.nil? || configuration.empty?

      adjust_schema_json(json, configuration)
    end

    private

    def adjust_schema_json(json, configuration)
      OpenProject::FieldRules.fail_open("adjusting schema", json) do
        JSON.dump(apply_field_rules(JSON.parse(json), configuration))
      end
    end

    # Hidden fields change the cached attribute groups, which the schema cache key does not know about.
    def json_key_dependencies
      dependencies = super
      OpenProject::FieldRules.fail_open("schema cache key", dependencies) do
        hidden = field_rules_schema_configuration&.select(&:hidden)&.map(&:key)
        [dependencies, (["field_rules", *hidden.sort].join(":") if hidden.present?)]
      end
    end

    def field_rules_schema_configuration
      return unless represented.respond_to?(:project) && represented.respond_to?(:type)
      return if represented.project.nil? || represented.type.nil?
      return if ::FieldRules::Resolver.system_actor?(User.current)

      ::FieldRules::Resolver.for(represented.project, represented.type)
    end

    def apply_field_rules(hash, configuration)
      work_package = represented.try(:work_package)
      empty_required = work_package ? ::FieldRules::Validator.grandfathered_fields(work_package, configuration) : []
      configuration.each do |field|
        key = ::FieldRules::Fields.schema_key(field.key)
        next if key.nil? || !hash.key?(key)

        if field.hidden
          remove_property(hash, key)
        else
          adjust_property(hash[key], field, empty_required.include?(field.key))
        end
      end
      remove_property(hash, "date") if %w[start_date due_date].all? { |key| configuration.hidden?(key) }
      hash
    end

    def remove_property(hash, key)
      hash.delete(key)
      remove_from_attribute_groups(hash, key)
    end

    # requiredButEmpty is the grandfather warning: an existing work package left empty a field that is now required.
    # It never blocks saving; the form can show "this field is required but empty".
    def adjust_property(property, field, required_but_empty = false)
      return unless property.is_a?(Hash)

      property["requiredButEmpty"] = true if required_but_empty

      property["required"] = true if field.required
      property["writable"] = false if field.read_only
      property["hasDefault"] = true if field.default_value.present?
    end

    def remove_from_attribute_groups(hash, key)
      Array(hash["_attributeGroups"]).each do |group|
        group["attributes"] = group["attributes"].reject { |attribute| attribute == key } if group.is_a?(Hash) && group["attributes"].is_a?(Array)
      end
    end
  end
end
