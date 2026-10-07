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

module API
  module V3
    module IssueView
      class ActivitiesParams
        DEFAULT_PAGE_SIZE = 20
        MAX_PAGE_SIZE = 100

        attr_reader :page, :per_page, :types

        def self.parse(params) = new(params)

        def initialize(params)
          @page = [params[:offset].to_i, 1].max
          @per_page = parse_per_page(params[:pageSize])
          @desc = parse_sort(params[:sortBy])
          @types = parse_types(params[:filters])
        end

        def desc? = @desc

        private

        def parse_per_page(raw)
          return DEFAULT_PAGE_SIZE if raw.nil?

          max = [MAX_PAGE_SIZE, Setting.apiv3_max_page_size].min
          size = raw.to_s.to_i
          return max if size == -1
          invalid!("pageSize") if size.negative?

          [size, max].min
        end

        def parse_sort(raw)
          return false if raw.nil?

          sort = parse_json(raw, "sortBy")
          valid = sort.is_a?(Array) && sort.size == 1 && sort.first.is_a?(Array) &&
                  sort.first.first == "timestamp" && %w[asc desc].include?(sort.first.last)
          invalid!("sortBy") unless valid

          sort.first.last == "desc"
        end

        def parse_types(raw)
          return if raw.nil?

          filters = parse_json(raw, "filters")
          valid = filters.is_a?(Array) && filters.size == 1 && filters.first.is_a?(Hash) && filters.first.keys == ["type"]
          condition = valid && filters.first["type"]
          valid &&= condition.is_a?(Hash) && condition["operator"] == "=" && condition["values"].is_a?(Array) &&
                    condition["values"].all? { |value| ::IssueView::ActivityNormalizer::TYPES.include?(value) }
          invalid!("filters") unless valid

          condition["values"]
        end

        def parse_json(raw, name)
          JSON.parse(raw)
        rescue JSON::ParserError, TypeError
          invalid!(name)
        end

        def invalid!(name)
          raise ::API::Errors::InvalidQuery.new(I18n.t("api_v3.errors.missing_or_malformed_parameter", parameter: name))
        end
      end
    end
  end
end
