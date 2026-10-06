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
  module Constraints
    DATE_KEY = "date"
    DATE_FIELDS = %w[start_date due_date].freeze

    module_function

    # TypeVariant keeps one constraint per attribute: wrap the existing one so other modules keep working.
    def install
      [*::FieldRules::Fields::NATIVE.keys, DATE_KEY].each do |key|
        existing = ::TypeVariant.attribute_constraints[key.to_sym]
        next if wrapped?(existing)

        ::TypeVariant.add_constraint(key, wrap(key, existing))
      end
    end

    # Logs attributes whose constraint is not ours (another engine overwrote the wrapper after install).
    def verify!
      [*::FieldRules::Fields::NATIVE.keys, DATE_KEY].each do |key|
        next if wrapped?(::TypeVariant.attribute_constraints[key.to_sym])

        Rails.logger.error("[field_rules] hidden constraint missing for #{key}: overwritten by another module")
      end
    end

    def wrapped?(callable)
      callable.respond_to?(:field_rules_wrapper?) && callable.field_rules_wrapper?
    end

    def wrap(key, existing)
      lambda do |variant, project: nil|
        (existing.nil? || existing.call(variant, project:)) && !hidden?(key, variant, project)
      end.tap { |wrapper| wrapper.define_singleton_method(:field_rules_wrapper?) { true } }
    end

    def hidden?(key, variant, project)
      return false if project.nil? || variant.nil?

      OpenProject::FieldRules.fail_open("hidden check", false, field: key, type_id: variant.type_id) do
        configuration = ::FieldRules::Resolver.for(project, variant.type_id)
        next DATE_FIELDS.all? { |field| configuration.hidden?(field) } if key == DATE_KEY

        configuration.hidden?(key)
      end
    end
  end
end
