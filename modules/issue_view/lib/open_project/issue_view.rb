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
  module IssueView
    require "open_project/issue_view/engine"

    CORE_DEPENDENCIES = {
      "WorkPackage#display_id" => -> { ::WorkPackage.method_defined?(:display_id) },
      "Relation.visible" => -> { ::Relation.respond_to?(:visible) },
      "WorkPackageRepresenter" => -> { defined?(::API::V3::WorkPackages::WorkPackageRepresenter) },
      "SpecificWorkPackageSchema" => -> { defined?(::API::V3::WorkPackages::Schema::SpecificWorkPackageSchema) },
      "ActivityPropertyFormatters" => -> { defined?(::API::V3::Activities::ActivityPropertyFormatters) },
      "API::Errors::InvalidQuery" => -> { defined?(::API::Errors::InvalidQuery) }
    }.freeze

    def self.assert_core_dependencies!
      missing = CORE_DEPENDENCIES.filter_map { |name, check| name unless check.call }
      return if missing.empty?

      raise "openproject-issue_view depends on core methods that are missing: #{missing.join(', ')}"
    end
  end
end
