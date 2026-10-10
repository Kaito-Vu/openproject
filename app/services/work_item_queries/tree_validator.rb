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
    # i18n scope of the problem keys (also the model's error keys for the tree attribute).
    I18N_SCOPE = "activerecord.errors.models.work_item_query.attributes.tree"

    module_function

    # Returns a list of [error key, interpolation options] problems; empty means valid.
    def errors(tree)
      return [[:root_not_group, {}]] unless group?(tree)

      state = { problems: [], nodes: 0, conditions: 0 }
      walk(tree, 1, state)
      problems = state[:problems]
      problems << [:too_many_nodes, { max: WorkItemQuery::MAX_NODES }] if state[:nodes] > WorkItemQuery::MAX_NODES
      if state[:conditions] > WorkItemQuery::MAX_CONDITIONS
        problems << [:too_many_conditions, { max: WorkItemQuery::MAX_CONDITIONS }]
      end
      problems.uniq
    end

    def messages(tree)
      errors(tree).map { |key, options| I18n.t(key, scope: I18N_SCOPE, **options) }
    end

    def walk(node, depth, state)
      state[:nodes] += 1
      # Stop walking (bounded work on hostile input); errors reports the node count.
      return if state[:nodes] > WorkItemQuery::MAX_NODES

      if group?(node)
        walk_group(node, depth, state)
      elsif node.is_a?(Hash) && node.key?("field")
        state[:conditions] += 1
        state[:problems].concat(token_problems(node), value_problems(node["values"]))
      else
        state[:problems] << [:invalid_node, {}]
      end
    end

    def walk_group(node, depth, state)
      problems = state[:problems]
      problems << [:unknown_op, { op: node["op"].inspect }] unless %w[and or].include?(node["op"])
      return problems << [:too_deep, { max: WorkItemQuery::MAX_DEPTH }] if depth > WorkItemQuery::MAX_DEPTH

      children = node["children"]
      return problems << [:children_not_array, {}] unless children.is_a?(Array)

      children.each { walk(it, depth + 1, state) }
    end

    def token_problems(node)
      tokens = node.values_at("field", "operator")
      problems = []
      problems << [:incomplete_condition, {}] unless tokens.all? { it.is_a?(String) && it.present? }
      if tokens.any? { it.is_a?(String) && it.length > WorkItemQuery::MAX_TOKEN_LENGTH }
        problems << [:token_too_long, { max: WorkItemQuery::MAX_TOKEN_LENGTH }]
      end
      problems
    end

    def value_problems(values)
      return [[:values_not_strings, {}]] unless values.is_a?(Array) && values.all?(String)

      problems = []
      problems << [:too_many_values, { max: WorkItemQuery::MAX_VALUES }] if values.size > WorkItemQuery::MAX_VALUES
      if values.any? { it.length > WorkItemQuery::MAX_VALUE_LENGTH }
        problems << [:value_too_long, { max: WorkItemQuery::MAX_VALUE_LENGTH }]
      end
      problems
    end

    def group?(node) = node.is_a?(Hash) && node.key?("children")

    private_class_method :walk, :walk_group, :token_problems, :value_problems, :group?
  end
end
