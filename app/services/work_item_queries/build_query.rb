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
  # Builds an unsaved Query that carries the compiled tree, so the regular
  # Query::Results / QueryRepresenter pipeline can run it.
  class BuildQuery
    def initialize(work_item_query, user:)
      @wiq = work_item_query
      @user = user
    end

    def call
      # include_subprojects is NOT NULL and validated (query.rb:55); without it the
      # query is invalid and Query#statement returns "1=0".
      query = Query.new(name: @wiq.name, user: @user, project: @wiq.project,
                        include_subprojects: Setting.display_subprojects_work_packages?,
                        show_hierarchies: @wiq.mode == "tree",
                        column_names: @wiq.columns.map { to_ar_name(it) },
                        sort_criteria: @wiq.sort_criteria.map { |name, dir| [to_ar_name(name), dir] })
      sql, leaves = Compiler.new(query).call(@wiq.tree)
      query.filters = leaves
      query.filter_tree_sql = sql
      query
    end

    private

    # WorkItemQuery stores API property names (e.g. assignee); Query expects AR names (assigned_to).
    def to_ar_name(name)
      ::API::Utilities::PropertyNameConverter.to_ar_name(name, context: WorkPackage.new)
    end
  end
end
