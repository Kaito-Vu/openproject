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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.

module WorkItemQueries
  module TreeValidator
    module_function

    # Returns a list of human readable problems; empty means valid.
    def errors(tree)
      problems = []
      count = 0
      walk = lambda do |node, depth|
        if node.is_a?(Hash) && node.key?("children")
          problems << "unknown op #{node['op'].inspect}" unless %w[and or].include?(node["op"])
          problems << "group nested deeper than #{WorkItemQuery::MAX_DEPTH}" if depth > WorkItemQuery::MAX_DEPTH
          children = node["children"]
          children.is_a?(Array) ? children.each { |c| walk.call(c, depth + 1) } : problems << "children must be an array"
        elsif node.is_a?(Hash) && node.key?("field")
          count += 1
          problems << "condition needs field and operator" if node["field"].blank? || node["operator"].blank?
          problems << "values must be an array" unless node["values"].is_a?(Array)
        else
          problems << "node must be a group or a condition"
        end
      end

      problems << "root must be a group" unless tree.is_a?(Hash) && tree.key?("children")
      walk.call(tree, 1) if problems.empty?
      problems << "more than #{WorkItemQuery::MAX_CONDITIONS} conditions" if count > WorkItemQuery::MAX_CONDITIONS
      problems.uniq
    end
  end
end
