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
  # Read-only queries behind the homescreen dashboard blocks.
  # Everything is scoped to what `user` may see.
  class DashboardStats
    DUE_SOON_DAYS = 7
    PORTFOLIO_LIMIT = 100

    attr_reader :user, :today

    def initialize(user: User.current, today: Time.zone.today)
      @user = user
      @today = today
    end

    # Open work packages assigned to the user.
    def assigned_open
      WorkPackage.visible(user).with_status_open.where(assigned_to_id: user.id)
    end

    def overdue
      assigned_open.where(due_date: ...today)
    end

    def due_today
      assigned_open.where(due_date: today)
    end

    # Due after today, up to and including DUE_SOON_DAYS from now.
    def due_soon
      assigned_open.where(due_date: (today + 1)..due_soon_until)
    end

    def due_soon_until
      today + DUE_SOON_DAYS
    end

    # Active projects the user is a direct member of.
    # ponytail: membership via groups is not counted, join Member -> group users if needed.
    def projects
      Project.visible(user).active.where(id: Member.where(user_id: user.id).select(:project_id))
    end

    # Every active project the user may see: the portfolio shown on the homescreen.
    def visible_projects
      Project.visible(user).active.workspace_type("project")
    end

    # ponytail: capped at PORTFOLIO_LIMIT projects (by name), page or pre-aggregate beyond that.
    def portfolio_ids
      @portfolio_ids ||= visible_projects.reorder(:name).limit(PORTFOLIO_LIMIT).pluck(:id)
    end

    def portfolio_metrics
      @portfolio_metrics ||= Projects::Metrics.new(portfolio_ids, user:, today:)
    end

    # Work package count per status for the user's assigned work, ordered like the status list.
    # @return [Array<[Status, Integer]>]
    def status_distribution
      counts = WorkPackage.visible(user).where(assigned_to_id: user.id).group(:status_id).count
      Status.where(id: counts.keys).order(:position).map { |status| [status, counts[status.id]] }
    end

    def recent_events(limit: 8)
      Activities::Fetcher
        .new(user, scope: :default)
        .events(from: 14.days.ago.to_datetime, to: 1.day.from_now.to_datetime, limit:)
        .first(limit)
    end
  end
end
