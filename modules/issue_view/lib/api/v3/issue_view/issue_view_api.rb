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
      class IssueViewAPI < ::API::OpenProjectAPI
        helpers do
          def private_response_headers
            header "Cache-Control", "private, no-cache"
            header "Vary", "Authorization, Cookie, Accept-Language"
          end

          def view_links(payload)
            wp_id = work_package.id
            permissions = payload[:permissions]
            counts = payload[:counts]
            children_filter = [{ parent: { operator: "=", values: [wp_id.to_s] } }].to_json

            { self: { href: api_v3_paths.work_package_issue_view(wp_id) },
              workPackage: { href: api_v3_paths.work_package(wp_id) },
              activities: { href: api_v3_paths.work_package_issue_view_activities(wp_id) },
              relations: { href: api_v3_paths.work_package_relations(wp_id) },
              children: { href: "#{api_v3_paths.work_packages}?#{{ filters: children_filter }.to_query}" },
              allowedStatuses: { href: api_v3_paths.work_package_form(wp_id), method: "post" },
              updateImmediately: (permissions[:edit] ? { href: api_v3_paths.work_package(wp_id), method: "patch" } : nil),
              addComment: (permissions[:comment] ? { href: api_v3_paths.work_package_activities(wp_id), method: "post" } : nil),
              attachments: (counts.key?(:attachments) ? { href: api_v3_paths.attachments_by_work_package(wp_id) } : nil),
              watchers: (counts.key?(:watchers) ? { href: api_v3_paths.work_package_watchers(wp_id) } : nil) }.compact
          end

          def activity_scope(params)
            scope = work_package.journals.internal_visible.meeting_cause_visible
                      .includes(:data, :customizable_journals, :attachable_journals, :storable_journals, :user)
            scope = scope.where.not(notes: [nil, ""]) if params.types == ["COMMENT"]
            scope.reorder(created_at: params.desc? ? :desc : :asc, id: params.desc? ? :desc : :asc)
          end

          def activity_page(scope, params, normalizer)
            filter_in_memory = params.types.present? && params.types != ["COMMENT"]
            return in_memory_page(scope, params, normalizer) if filter_in_memory

            total = scope.count
            journals = params.per_page.zero? ? [] : scope.offset((params.page - 1) * params.per_page).limit(params.per_page).to_a
            [total, journals.flat_map { |journal| filtered_events(normalizer, journal, params) }]
          end

          def in_memory_page(scope, params, normalizer)
            matching = scope.to_a.map { |journal| [journal, filtered_events(normalizer, journal, params)] }
                            .reject { |_, events| events.empty? }
            window = params.per_page.zero? ? [] : matching.slice((params.page - 1) * params.per_page, params.per_page).to_a
            [matching.size, window.flat_map(&:last)]
          end

          def filtered_events(normalizer, journal, params)
            events = normalizer.events(journal)
            params.types ? events.select { |event| params.types.include?(event[:type]) } : events
          end
        end

        resources :issue_view do
          get do
            private_response_headers
            payload = ::IssueView::Builder.call(work_package, current_user)

            { _type: "IssueView", **payload, _links: view_links(payload) }
          end

          resources :activities do
            get do
              private_response_headers
              query = ActivitiesParams.parse(params)
              normalizer = ::IssueView::ActivityNormalizer.new(work_package)
              total, events = activity_page(activity_scope(query), query, normalizer)

              { _type: "Collection",
                total:,
                count: events.size,
                pageSize: query.per_page,
                offset: query.page,
                _embedded: { elements: events },
                _links: { self: { href: api_v3_paths.work_package_issue_view_activities(work_package.id) } } }
            end
          end
        end
      end
    end
  end
end
