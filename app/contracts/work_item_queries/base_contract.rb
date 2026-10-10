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

module WorkItemQueries
  # Checks shared by saving and by running an unsaved query (POST /execute).
  # Saving adds the save_queries and public checks (see CreateContract and UpdateContract).
  class BaseContract < ::ModelContract
    attribute :name
    attribute :mode
    attribute :public
    attribute :project_id
    attribute :columns
    attribute :sort_criteria
    attribute :tree

    def self.model
      WorkItemQuery
    end

    validate :user_logged_in
    validate :validate_project

    private

    def user_logged_in
      errors.add :base, :error_unauthorized unless user.logged?
    end

    def validate_project
      errors.add :project, :error_not_found unless project_visible?
    end

    def project_visible?
      return @project_visible if defined?(@project_visible)

      @project_visible = model.project_id.nil? || Project.visible(user).exists?(id: model.project_id)
    end

    # Mirrors Queries::BaseContract#user_allowed_to_save_queries?
    # Skipped for an invisible project: that is reported on :project, not as a 403.
    def user_allowed_to_save
      return unless project_visible?

      errors.add :base, :error_unauthorized unless allowed?(:save_queries)
    end

    # Unlike Queries::BaseContract, also checked when an already public query moves to another
    # project, so it cannot be published in a project where the user may not manage public queries.
    def user_allowed_to_make_public
      return unless project_visible? && model.public && (model.public_changed? || model.project_id_changed?)

      errors.add :public, :not_allowed unless allowed?(:manage_public_queries)
    end

    def allowed?(permission)
      if model.project
        user.allowed_in_project?(permission, model.project)
      else
        user.allowed_in_any_project?(permission)
      end
    end
  end
end
