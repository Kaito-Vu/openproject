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
  class Values
    SCALARS = { "String" => "string", "Integer" => "integer", "Float" => "float", "Duration" => "duration",
                "Date" => "date", "DateTime" => "datetime", "Boolean" => "bool" }.freeze

    def initialize(context, permissions)
      @context = context
      @permissions = permissions
    end

    def property_for(key) = ::API::Utilities::PropertyNameConverter.from_ar_name(key)

    def key_for(property)
      match = property.to_s.match(/\AcustomField(\d+)\z/)
      match ? "custom_field_#{match[1]}" : property.to_s.underscore
    end

    def field(key, state: nil)
      property = property_for(key)
      definition = @context.schema_json[property]
      return unless definition.is_a?(Hash)

      data_type, value = typed_value(property, definition["type"].to_s)
      editable, reason = editability(key, definition["writable"], state, data_type)
      { dataType: data_type, value:, editable:, editableReason: reason }
    end

    def label(key)
      @context.schema_json.dig(property_for(key), "name")
    end

    private

    def typed_value(property, type)
      json = @context.wp_json
      links = json.fetch("_links", {})

      if type == "Formattable"
        ["formattable", json[property] || { "format" => "markdown", "raw" => "", "html" => "" }]
      elsif SCALARS.key?(type)
        raw = json[property]
        [SCALARS[type], { raw:, display: display(type, raw) }]
      elsif type.start_with?("[]")
        items = Array(links[property])
        ["linkList", { raw: items.map { |link| id_of(link) }, display: items.map { |link| link["title"] } }]
      elsif links.key?(property)
        link = links[property]
        ["link", { raw: link && id_of(link), display: link && link["title"] }]
      else
        ["unknown", { raw: nil, display: nil }]
      end
    end

    def display(type, raw)
      return if raw.nil?
      return raw.to_s unless %w[Date DateTime].include?(type)

      type == "Date" ? I18n.l(Date.iso8601(raw)) : I18n.l(Time.iso8601(raw))
    rescue ArgumentError
      raw.to_s
    end

    def id_of(link)
      tail = link["href"].to_s.split("/").last
      tail.match?(/\A\d+\z/) ? tail.to_i : tail
    end

    def editability(key, writable, state, data_type)
      return [false, denied_reason] unless @permissions[:edit]
      return [@permissions[:transition], (@permissions[:transition] ? nil : "workflow")] if key == "status"
      return [false, "not_writable"] if !writable || data_type == "unknown"
      return [false, "read_only"] if state && state[:readOnly]

      [true, nil]
    end

    def denied_reason
      work_package = @context.work_package
      @context.user.allowed_in_work_package?(:edit_work_packages, work_package) ? "locked" : "no_permission"
    end
  end
end
