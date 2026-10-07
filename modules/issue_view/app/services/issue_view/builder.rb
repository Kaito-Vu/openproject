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

module IssueView
  class Builder
    Context = Data.define(:work_package, :user, :wp_json, :schema, :schema_json)

    def self.call(work_package, user)
      new(work_package, user).call
    end

    def initialize(work_package, user)
      @work_package = work_package
      @user = user
    end

    def call
      context = build_context
      permissions = Permissions.call(context)
      layout = Layout.call(context, Values.new(context, permissions), show_diagnostics: @user.admin?)

      { id: @work_package.id,
        identifier: @work_package.display_id,
        subject: @work_package.subject,
        header:,
        permissions:,
        counts: Counts.call(@work_package, @user),
        parent: Counts.parent(@work_package, @user),
        lockVersion: @work_package.lock_version }.merge(layout)
    end

    private

    def build_context
      schema = ::API::V3::WorkPackages::Schema::SpecificWorkPackageSchema.new(work_package: @work_package)
      wp_representer = ::API::V3::WorkPackages::WorkPackageRepresenter
                         .create(@work_package, current_user: @user, embed_links: false)
      Context.new(work_package: @work_package, user: @user,
                  wp_json: JSON.parse(wp_representer.to_json),
                  schema:,
                  schema_json: JSON.parse(schema_representer(schema).to_json))
    end

    def schema_representer(schema)
      ::API::V3::WorkPackages::Schema::WorkPackageSchemaRepresenter
        .create(schema, self_link: nil, form_embedded: true, current_user: @user)
    end

    def header
      paths = ::API::V3::Utilities::PathHelper::ApiV3Path
      { type: ref(@work_package.type, paths.type(@work_package.type_id)),
        status: ref(@work_package.status, paths.status(@work_package.status_id),
                    isClosed: @work_package.status&.is_closed?),
        priority: ref(@work_package.priority, paths.priority(@work_package.priority_id)),
        assignee: ref(@work_package.assigned_to, paths.user(@work_package.assigned_to_id)),
        author: ref(@work_package.author, paths.user(@work_package.author_id)) }
    end

    def ref(record, href, **extra)
      return unless record

      { id: record.id, name: record.name, **extra, _links: { self: { href: } } }
    end
  end
end
