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

module OpenProject
  module FieldRules
    require "open_project/field_rules/engine"

    PATCH_TARGETS = {
      "WorkPackages::BaseContract" => %i[writable_attributes validate_enabled_type],
      "WorkPackages::SetAttributesService" => %i[set_calculated_attributes update_derivable_date_attribute],
      "API::V3::WorkPackages::Schema::WorkPackageSchemaRepresenter" => %i[to_json json_key_dependencies]
    }.freeze

    # Arity of the overridden methods (-1 = variable arguments); the patches call super, so a changed core
    # signature would break them at runtime. Checked at boot and only logged.
    PATCH_ARITIES = {
      writable_attributes: 0, validate_enabled_type: 0, set_calculated_attributes: 1,
      update_derivable_date_attribute: 0, to_json: -1, json_key_dependencies: 0
    }.freeze

    # Runs the block; on StandardError logs it (class, message, context), reports it and returns +fallback+, so a
    # field rules failure never breaks work package handling but stays observable.
    def self.fail_open(where, fallback, **context)
      yield
    rescue StandardError => e
      detail = context.map { |key, value| " #{key}=#{value.inspect}" }.join
      Rails.logger.error("[field_rules] #{where} failed, failing open: #{e.class}: #{e.message}#{detail}")
      begin
        Rails.error.report(e, handled: true, context: context.merge(where:))
      rescue StandardError
        nil
      end
      fallback
    end

    def self.assert_patch_targets!
      PATCH_TARGETS.each do |class_name, methods|
        klass = class_name.constantize
        missing = methods.reject { |name| klass.method_defined?(name) || klass.private_method_defined?(name) }
        unless missing.empty?
          raise "openproject-field_rules patches #{class_name}##{missing.join(', #')}, which core no longer defines"
        end

        methods.each { |name| check_arity(klass, name) }
      end
      raise "openproject-field_rules needs TypeVariant.add_constraint" unless TypeVariant.respond_to?(:add_constraint)
    end

    def self.check_arity(klass, name)
      expected = PATCH_ARITIES[name]
      actual = klass.instance_method(name).arity
      return if expected.nil? || actual == expected

      Rails.logger.error("[field_rules] #{klass}##{name} has arity #{actual}, expected #{expected}: "                          "core signature changed, the field rules patch may break")
    end
  end
end
