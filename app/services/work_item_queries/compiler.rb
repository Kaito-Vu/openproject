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
  # Turns a condition tree into a single SQL boolean expression and the list of
  # filter instances (needed by Query::Results for joins/includes).
  class Compiler
    class InvalidTree < StandardError; end

    def self.or_unsafe?(filter)
      filter.from.present? || !Array(filter.joins).all?(Symbol)
    end

    def initialize(query)
      @query = query
      @leaves = []
    end

    def call(tree)
      problems = TreeValidator.errors(tree)
      raise InvalidTree, problems.to_sentence if problems.any?

      sql = compile_group(tree, inside_or: false)
      [sql.presence || "TRUE", @leaves]
    end

    private

    def compile(node, inside_or:)
      node.key?("children") ? compile_group(node, inside_or:) : compile_condition(node, inside_or:)
    end

    def compile_group(group, inside_or:)
      inside_or ||= group["op"] == "or"
      parts = group["children"].map { |child| compile(child, inside_or:) }.compact_blank
      return nil if parts.empty?

      "(#{parts.join(" #{group['op'].upcase} ")})"
    end

    def compile_condition(node, inside_or:)
      filter = build_filter(node)
      if inside_or && self.class.or_unsafe?(filter)
        raise InvalidTree, "#{node['field']} cannot be used inside an OR group"
      end

      @leaves << filter
      "(#{filter.where})"
    end

    def build_filter(node)
      key = ::API::Utilities::QueryFiltersNameConverter.to_ar_name(node["field"], refer_to_ids: true)
      filter = ::Queries::WorkPackages::FilterSerializer.filter_for(key, no_memoization: true)
      filter.context = @query
      filter.operator = node["operator"]
      filter.values = node["values"]
      raise InvalidTree, "invalid condition on #{node['field']}" unless filter.available? && filter.valid?

      filter
    end
  end
end
