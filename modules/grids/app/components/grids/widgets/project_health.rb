# frozen_string_literal: true

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

module Grids
  module Widgets
    # Computed health and key figures of one project, shown at the top of its overview.
    class ProjectHealth < Grids::WidgetComponent
      include ProjectStatusHelper

      param :project

      def title
        I18n.t("project_dashboard.health_widget.title")
      end

      def wrapper_arguments
        { full_width: true }
      end

      def can_view?
        current_user.allowed_in_project?(:view_work_packages, project)
      end

      def row
        @row ||= Projects::Metrics.new([project.id], user: current_user)[project.id]
      end

      def list_path(*filters)
        helpers.project_work_packages_path(project, query_props: { f: filters }.to_json)
      end

      # @return [Array<Hash>] key, value, optional href and danger flag per card
      def cards
        open = { n: "status", o: "o", v: [] }
        [
          { key: :progress, value: "#{row.progress}%" },
          { key: :open, value: row.open, href: list_path(open) },
          { key: :overdue, value: row.overdue, danger: true,
            href: list_path(open, { n: "dueDate", o: "<>d", v: ["", (Time.zone.today - 1).iso8601] }) },
          { key: :unassigned, value: row.unassigned, href: list_path(open, { n: "assignee", o: "!*", v: [] }) },
          { key: :schedule, value: row.planned ? "#{row.planned}%" : "–" }
        ]
      end
    end
  end
end
