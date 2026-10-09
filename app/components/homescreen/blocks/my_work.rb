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
    class MyWork < DashboardBlock
      LIMIT = 5

      def title
        I18n.t("homescreen.dashboard.my_work.title")
      end

      # @return [Array<Hash>] key and up to LIMIT work packages for each deadline group
      def groups
        @groups ||= {
          overdue: stats.overdue,
          today: stats.due_today,
          soon: stats.due_soon
        }.map do |key, scope|
          { key:, work_packages: scope.includes(:project, :status).reorder(:due_date, :id).limit(LIMIT).to_a }
        end
      end

      def empty?
        groups.all? { |group| group[:work_packages].empty? }
      end
    end
  end
end
