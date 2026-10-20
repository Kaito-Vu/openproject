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
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Projects
  class DeleteProjectJob < UserJob
    queue_with_priority :below_normal
    include OpenProject::LocaleHelper
    include GoodJob::ActiveJobExtensions::Concurrency

    # Every project deletion renumbers lft/rgt of the whole nested set, so parallel deletions deadlock.
    # Excess jobs are retried by GoodJob once the running one is done.
    good_job_control_concurrency_with(perform_limit: 1, key: -> { "projects-delete" })

    # The project is already gone, e.g. deleted along with its parent by an earlier job.
    discard_on ActiveJob::DeserializationError

    attr_reader :project

    def execute(project:)
      @project = project

      service_call = ::Projects::DeleteService.new(user:, model: project).call

      if service_call.failure?
        OpenProject.logger.error("Failed to delete project #{project} in background job: " \
                                 "#{service_call.message}")
      end
    rescue StandardError => e
      OpenProject.logger.error("Encountered an error when trying to delete project " \
                               "'#{project}' : #{e.message} #{e.backtrace.join("\n")}")
    end
  end
end
