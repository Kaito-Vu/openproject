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
  class Permissions
    def self.call(context)
      new(context).call
    end

    def initialize(context)
      @context = context
      @links = context.wp_json.fetch("_links", {})
    end

    def call
      edit = link?(:updateImmediately)

      { view: true,
        edit:,
        delete: link?(:delete),
        comment: link?(:addComment),
        transition: edit && transition?,
        addRelation: link?(:addRelation),
        manageWatchers: link?(:addWatcher) || link?(:removeWatcher),
        addAttachment: link?(:addAttachment),
        logTime: link?(:logTime) }
    end

    private

    def link?(name) = @links.key?(name.to_s)

    def transition?
      work_package = @context.work_package
      @context.schema.assignable_statuses.any? { |status| status.id != work_package.status_id }
    end
  end
end
