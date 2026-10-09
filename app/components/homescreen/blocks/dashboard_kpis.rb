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

module Homescreen
  module Blocks
    class DashboardKpis < DashboardBlock
      def title
        I18n.t("homescreen.dashboard.kpis.title")
      end

      def wrapper_arguments
        { full_width: true }
      end

      # @return [Array<Hash>] key, value, href and optional danger flag per card
      def cards
        today = stats.today
        [
          { key: :assigned, value: stats.assigned_open.count, href: wp_list_path(*my_open_filters) },
          { key: :overdue, value: stats.overdue.count, danger: true,
            href: wp_list_path(*my_open_filters, due_between_filter(nil, today - 1)) },
          { key: :due_soon,
            value: stats.assigned_open.where(due_date: today..stats.due_soon_until).count,
            href: wp_list_path(*my_open_filters, due_between_filter(today, stats.due_soon_until)) },
          { key: :projects, value: stats.projects.count, href: helpers.projects_path }
        ]
      end
    end
  end
end
