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
  class Layout
    def self.call(context, values, show_diagnostics:)
      new(context, values, show_diagnostics:).call
    end

    def initialize(context, values, show_diagnostics:)
      @context = context
      @values = values
      @show_diagnostics = show_diagnostics
      @unavailable = []
    end

    def call
      resolved = resolve_screen
      result = if resolved.respond_to?(:screen?) && resolved.screen?
                 from_screen(resolved)
               else
                 from_native(reason_for(resolved))
               end
      result[:diagnostics] = diagnostics(resolved) if @show_diagnostics
      result
    end

    private

    def resolve_screen
      return "module_disabled" unless defined?(::Screens::Resolver)

      work_package = @context.work_package
      ::IssueView::FailOpen.call("screen resolve", work_package_id: work_package.id) do
        ::Screens::Resolver.for(work_package.project, work_package.type, :view)
      end
    end

    def reason_for(resolved)
      case resolved
      when String then resolved
      when ::IssueView::FailOpen::ERROR then "error"
      else resolved.reason
      end
    end

    def from_screen(resolved)
      sections = resolved.sections.map do |section|
        { id: section[:id].to_s,
          name: section[:name],
          position: section[:position],
          fields: section[:fields].filter_map { |field| screen_field(field) } }
      end
      { source: "screen", reason: nil, sections: }
    end

    def screen_field(field)
      value = @values.field(field[:key], state: field[:state])
      unless value
        @unavailable << field[:key]
        return
      end

      value.merge(key: field[:key], label: field[:label], position: field[:position],
                  width: field[:width], state: field[:state])
    end

    def from_native(reason)
      groups = Array(@context.schema_json["_attributeGroups"])
                 .select { |group| group["_type"] == "WorkPackageFormAttributeGroup" }
      sections = groups.each_with_index.map do |group, index|
        { id: (index + 1).to_s, name: group["name"], position: index + 1,
          fields: native_fields(group["attributes"]) }
      end
      { source: "native", reason:, sections: }
    end

    def native_fields(properties)
      Array(properties).each_with_index.filter_map do |property, index|
        key = @values.key_for(property)
        value = @values.field(key)
        next unless value

        value.merge(key:, label: @values.label(key), position: index + 1, width: "full", state: nil)
      end
    end

    def diagnostics(resolved)
      diag = resolved.respond_to?(:diagnostics) ? resolved.diagnostics : {}
      { unavailable: (Array(diag[:unavailable]) + @unavailable).uniq,
        hiddenButPlaced: Array(diag[:hidden_but_placed]) }
    end
  end
end
