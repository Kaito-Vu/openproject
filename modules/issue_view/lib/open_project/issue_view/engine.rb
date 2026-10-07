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

require "open_project/plugins"

module OpenProject::IssueView
  class Engine < ::Rails::Engine
    engine_name :openproject_issue_view

    include OpenProject::Plugins::ActsAsOpEngine

    register "openproject-issue_view",
             author_url: "https://www.openproject.org",
             bundled: true

    add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id do
      mount ::API::V3::IssueView::IssueViewAPI
    end

    add_api_path :work_package_issue_view do |id|
      "#{work_package(id)}/issue_view"
    end

    add_api_path :work_package_issue_view_activities do |id|
      "#{work_package_issue_view(id)}/activities"
    end

    config.to_prepare do
      OpenProject::IssueView.assert_core_dependencies!
    end
  end
end
