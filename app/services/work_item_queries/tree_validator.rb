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
  module TreeValidator
    module_function

    def present_string?(value) = value.is_a?(String) && value.present?

    # i18n scope of the problem keys (also the model's error keys for the tree attribute).
    I18N_SCOPE = "activerecord.errors.models.work_item_query.attributes.tree"

    # Returns a list of [error key, interpolation options] problems; empty means valid.
    def errors(tree)
      problems = []
      count = 0
      walk = lambda do |node, depth|
        if node.is_a?(Hash) && node.key?("children")
          problems << [:unknown_op, { op: node["op"].inspect }] unless %w[and or].include?(node["op"])
          if depth > WorkItemQuery::MAX_DEPTH
            problems << [:too_deep, { max: WorkItemQuery::MAX_DEPTH }]
            next
          end
          children = node["children"]
          children.is_a?(Array) ? children.each { |c| walk.call(c, depth + 1) } : problems << [:children_not_array, {}]
        elsif node.is_a?(Hash) && node.key?("field")
          count += 1
          problems << [:incomplete_condition, {}] unless present_string?(node["field"]) && present_string?(node["operator"])
          problems << [:values_not_strings, {}] unless node["values"].is_a?(Array) && node["values"].all?(String)
        else
          problems << [:invalid_node, {}]
        end
      end

      problems << [:root_not_group, {}] unless tree.is_a?(Hash) && tree.key?("children")
      walk.call(tree, 1) if problems.empty?
      problems << [:too_many_conditions, { max: WorkItemQuery::MAX_CONDITIONS }] if count > WorkItemQuery::MAX_CONDITIONS
      problems.uniq
    end

    def messages(tree)
      errors(tree).map { |key, options| I18n.t(key, scope: I18N_SCOPE, **options) }
    end
  end
end
