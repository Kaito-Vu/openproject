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

require Rails.root.join("db/migrate/migration_utils/utils")

class FillFromGitlab < ActiveRecord::Migration[8.1]
  include Migration::Utils

  def up
    mr_url = execute("SELECT gitlab_html_url FROM gitlab_merge_requests WHERE gitlab_html_url != '' ORDER BY id DESC LIMIT 1").first&.fetch("gitlab_html_url")
    issue_url = execute("SELECT gitlab_html_url FROM gitlab_issues WHERE gitlab_html_url != '' ORDER BY id DESC LIMIT 1").first&.fetch("gitlab_html_url")
    return if mr_url.blank? && issue_url.blank?

    base_url = URI.parse(mr_url.presence || issue_url).tap { |u| u.path = "" }
    options = Setting.plugin_openproject_gitlab_integration.merge(url: base_url)
    ActiveRecord::Base.transaction do
      execute(<<-SQL.squish)
        INSERT INTO repository_providers (name, type, options, created_at, updated_at)
        VALUES('GitLab', 'Repositories::GitlabProvider', '#{options.to_json}', NOW(), NOW())
      SQL

      provider_id = execute("SELECT id FROM repository_providers WHERE type = 'Repositories::GitlabProvider' LIMIT 1").first&.fetch("id")

      execute(<<-SQL.squish)
        INSERT INTO repository_users(provider_id, external_id, name, username, avatar_url, created_at, updated_at)
        SELECT #{provider_id}, gitlab_id, name, username, avatar_url, created_at, updated_at FROM gitlab_users
      SQL

      # TODO: we need to convert from gitlab_user_id to repository_user_id!!!
      execute(<<-SQL.squish)
        INSERT INTO repository_issues(
          provider_id,
          repository_user_id,
          external_id,
          number,
          html_url,
          state,
          project_name,
          title,
          body,
          labels,
          external_updated_at,
          created_at,
          updated_at
        )
        SELECT
          #{provider_id},
          gitlab_user_id,
          gitlab_id,
          number,
          gitlab_html_url,
          state,
          repository,
          title,
          body,
          labels,
          gitlab_updated_at,
          created_at,
          updated_at
        FROM gitlab_issues
      SQL

      # TODO: Migrate existing merge requests and pipelines as well

      binding.pry
      raise "Don't want to succeed yet."
    end
  end

  def down
    # no-op, downing this migration won't do anything, but downing the preceding migrations will remove corresponding data
  end
end
