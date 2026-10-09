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

module Projects
  # Work package based figures and a computed health signal for a set of projects.
  # Shared by the homescreen portfolio and the project overview, so both show the same numbers.
  # Everything is limited to the work packages `user` may see.
  class Metrics
    Row = Struct.new(:open, :overdue, :unassigned, :closed, :progress, :planned, :health, keyword_init: true)
    Member = Struct.new(:user, :open, :overdue, :closed_recent, :progress, keyword_init: true)

    HEALTH_ORDER = %i[no_data healthy attention risk].freeze
    # Share of open work packages that are overdue / points progress lags behind the elapsed schedule.
    ATTENTION = { overdue_ratio: 0.10, gap: 10 }.freeze
    RISK = { overdue_ratio: 0.25, gap: 25 }.freeze
    RECENT_DAYS = 30

    attr_reader :user, :today

    def initialize(project_ids, user: User.current, today: Time.zone.today)
      @project_ids = Array(project_ids)
      @user = user
      @today = today
    end

    # @return [Row] an empty row for projects without visible work packages
    def [](project_id)
      rows.fetch(project_id) { build_row({}, nil) }
    end

    # Per-project progress in percent: average of the leaf work packages' done_ratio weighted by
    # estimated hours (1 when unestimated). Parents are left out as their value derives from children.
    def progress
      leaf_progress(base, :project_id)
    end

    # One row per visible project member who is a user, busiest first.
    # ponytail: "closed recently" uses updated_at of closed work packages, there is no closed_at column.
    # @param members [Enumerable<User>]
    def team(project_id, members)
      ids = members.map(&:id)
      scope = base.where(project_id:, assigned_to_id: ids)
      counts = scope.joins(:status).group(:assigned_to_id).pluck(:assigned_to_id, *member_counts)
                    .to_h { |id, *figures| [id, figures] }
      member_progress = leaf_progress(scope, :assigned_to_id)

      members.map do |member|
        open, overdue, recent = counts.fetch(member.id, [0, 0, 0])
        Member.new(user: member, open:, overdue:, closed_recent: recent, progress: member_progress[member.id])
      end.sort_by { |m| [-m.open, m.user.name] }
    end

    private

    def base
      WorkPackage.visible(user).where(project_id: @project_ids)
    end

    def rows
      @rows ||= begin
        figures = base.joins(:status).group(:project_id).pluck(:project_id, *row_counts)
        progress_by_project = progress
        figures.to_h do |project_id, open, overdue, unassigned, closed, first_start, last_due|
          [project_id, build_row({ open:, overdue:, unassigned:, closed:, first_start:, last_due: },
                                 progress_by_project[project_id])]
        end
      end
    end

    def build_row(figures, progress)
      open = figures[:open].to_i
      overdue = figures[:overdue].to_i
      planned = planned_percent(figures[:first_start], figures[:last_due])
      row = Row.new(open:, overdue:, unassigned: figures[:unassigned].to_i, closed: figures[:closed].to_i,
                    progress: progress || 0, planned:)
      row.health = health(row)
      row
    end

    def planned_percent(first_start, last_due)
      return unless first_start && last_due && last_due > first_start

      (((today - first_start).to_f / (last_due - first_start)) * 100).clamp(0, 100).round
    end

    def health(row)
      return :no_data if row.open + row.closed == 0

      ratio = row.open.zero? ? 0 : row.overdue.fdiv(row.open)
      gap = row.planned ? row.planned - row.progress : 0

      if ratio >= RISK[:overdue_ratio] || gap >= RISK[:gap]
        :risk
      elsif ratio >= ATTENTION[:overdue_ratio] || gap >= ATTENTION[:gap]
        :attention
      else
        :healthy
      end
    end

    def row_counts
      [
        count_where("statuses.is_closed = false"),
        count_where("statuses.is_closed = false AND work_packages.due_date < ?", today),
        count_where("statuses.is_closed = false AND work_packages.assigned_to_id IS NULL"),
        count_where("statuses.is_closed = true"),
        Arel.sql("MIN(work_packages.start_date)"),
        Arel.sql("MAX(work_packages.due_date)")
      ]
    end

    def member_counts
      [
        count_where("statuses.is_closed = false"),
        count_where("statuses.is_closed = false AND work_packages.due_date < ?", today),
        count_where("statuses.is_closed = true AND work_packages.updated_at >= ?", today - RECENT_DAYS)
      ]
    end

    def count_where(condition, *binds)
      Arel.sql(WorkPackage.sanitize_sql_array(["COUNT(*) FILTER (WHERE #{condition})", *binds]))
    end

    def leaf_progress(scope, group_column)
      weight = "COALESCE(NULLIF(work_packages.estimated_hours, 0), 1)"
      leaves = scope.where.not(id: WorkPackage.where.not(parent_id: nil).select(:parent_id))

      leaves
        .joins(:status)
        .where(statuses: { excluded_from_totals: false })
        .group(group_column)
        .pluck(group_column,
               Arel.sql("SUM(COALESCE(work_packages.done_ratio, 0) * #{weight}) / SUM(#{weight})"))
        .to_h { |id, percent| [id, percent.round] }
    end
  end
end
