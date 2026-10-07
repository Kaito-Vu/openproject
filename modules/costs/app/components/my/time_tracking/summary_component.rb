# frozen_string_literal: true

# -- copyright
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
# ++
module My
  module TimeTracking
    # KPI strip above every view: logged vs. scheduled hours, progress, running timer and a
    # per-project breakdown for the displayed period.
    class SummaryComponent < ApplicationComponent
      include ScheduledHours

      options :time_entries, :date, :mode

      PROJECT_COLORS = %w[#3a86ff #06a77d #f4a261 #9b5de5 #e63946 #00b4d8].freeze

      def logged = @logged ||= time_entries.sum(&:hours_for_calculation).round(2)

      def scheduled = @scheduled ||= working_hours.values.sum.round(2)

      def difference = (logged - scheduled).round(2)

      def progress
        return (logged.positive? ? 100 : 0) unless scheduled.positive?

        [(logged / scheduled * 100).round, 100].min
      end

      def ongoing = @ongoing ||= time_entries.find(&:ongoing?)

      def entry_count = time_entries.size

      def project_count = time_entries.map(&:project_id).uniq.size

      def fmt(hours)
        DurationConverter.output(hours.abs, format: :hours_and_minutes).presence || "0h"
      end

      def period_label
        if mode == :day
          date.today? ? t(:label_today_capitalized) : I18n.l(date, format: :long)
        else
          t("label_#{mode}")
        end
      end

      # Top projects by hours; ponytail: anything beyond the palette is dropped from the bar.
      def breakdown
        @breakdown ||= time_entries
          .group_by(&:project)
          .map { |project, entries| [project, entries.sum(&:hours_for_calculation)] }
          .sort_by { |_, hours| -hours }
          .first(PROJECT_COLORS.size)
          .each_with_index
          .map do |(project, hours), i|
            { name: project.name, hours:, color: PROJECT_COLORS[i], pct: logged.zero? ? 0 : (hours / logged * 100).round(1) }
          end
      end
    end
  end
end
