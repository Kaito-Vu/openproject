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
  module ContractPatch
    def writable_attributes
      attributes = super
      @field_rules_core_writable = attributes
      # Copying a whole project deliberately bypasses the rules: values hidden or read-only under the rules of the
      # source project must survive the copy (documented in docs/api project_type_field_rules and the module specs).
      return attributes if is_a?(::WorkPackages::CopyProjectContract)

      configuration = field_rules_configuration
      return attributes if configuration.empty?

      attributes.reject { |attribute| configuration.restricting_write(attribute) }
    end

    private

    # Also overridden by openproject-type_schemes. Both patches call +super+ first and only add their own
    # errors afterwards, so the prepend order does not matter and both checks stay in effect.
    def validate_enabled_type
      super
      add_field_rule_errors
    end

    def writable_by_user?(field_key)
      Array(@field_rules_core_writable).any? { |attribute| ::FieldRules::Fields.attribute_matches?(field_key, attribute) }
    end

    def field_rules_configuration
      return ::FieldRules::EffectiveConfiguration.empty if ::FieldRules::Resolver.system_actor?(@user)

      OpenProject::FieldRules.fail_open("resolving rules", ::FieldRules::EffectiveConfiguration.empty,
                                        project_id: model.project_id, type_id: model.type_id) do
        ::FieldRules::Resolver.for(model.project_id, model.type_id)
      end
    end

    def add_field_rule_errors
      OpenProject::FieldRules.fail_open("required check", nil, project_id: model.project_id, type_id: model.type_id) do
        writable_attributes
        ::FieldRules::Validator.violations(model, user: @user).each do |violation|
          next unless writable_by_user?(violation.field)

          errors.add(violation.attribute.delete_suffix("_id").to_sym, :required_by_field_rules, type: model.type&.name)
        end
        add_restricted_target_versions_error
      end
    end

    # Version assignments bypass the changed attributes the readonly check looks at.
    def add_restricted_target_versions_error
      return unless field_rules_configuration.restricting_write("target_versions")
      return unless model.target_versions_changed? && !model.system_version_override?("target")

      errors.add(:target_versions, :error_readonly)
    end
  end
end
