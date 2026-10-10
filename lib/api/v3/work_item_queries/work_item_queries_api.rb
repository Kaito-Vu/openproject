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

module API
  module V3
    module WorkItemQueries
      class WorkItemQueriesAPI < ::API::OpenProjectAPI
        resources :work_item_queries do
          helpers ::API::V3::Queries::Helpers::QueryRepresenterResponse

          helpers do
            def find_visible!
              WorkItemQuery.visible(current_user).find_by(id: params[:id]) || raise(::API::Errors::NotFound)
            end

            # Runs an unsaved query from the request body (same payload as POST, nothing is persisted).
            def adhoc_query
              attributes = ::API::V3::ParseResourceParamsService
                             .new(current_user, model: WorkItemQuery, representer: WorkItemQueryPayloadRepresenter)
                             .call(request_body)
                             .result
              call = ::WorkItemQueries::SetAttributesService
                       .new(user: current_user, model: WorkItemQuery.new(name: "adhoc"),
                            contract_class: ::WorkItemQueries::BaseContract)
                       .call(attributes)
              raise ::API::Errors::ErrorBase.create_and_merge_errors(call.errors) if call.failure?

              call.result
            end

            # Responds with the regular QueryRepresenter (columns, sortBy, embedded results).
            def run_query(wiq)
              query = begin
                ::WorkItemQueries::BuildQuery.new(wiq, user: current_user).call
              rescue ::WorkItemQueries::Compiler::InvalidTree => e
                raise ::API::Errors::Validation.new(:tree, e.message)
              end
              query_representer_response(query, params.slice(:pageSize, :offset).to_h.symbolize_keys)
            end
          end

          # Authentication happens in after_validation, so authorize there too (a `before`
          # block would still see the anonymous user).
          after_validation do
            authorize_by_with_raise(current_user.logged?) { raise ::API::Errors::Unauthenticated }
            authorize_in_any_work_package(:view_work_packages)
          end

          get do
            records = WorkItemQuery.visible(current_user).includes(:user, :updated_by, :project).order(:name).to_a
            # Only the current user's favorites, for WorkItemQuery#favorite_of?.
            ActiveRecord::Associations::Preloader.new(records:, associations: :favorites,
                                                      scope: WorkItemQueryFavorite.where(user: current_user)).call
            WorkItemQueryCollectionRepresenter.new(records, self_link: api_v3_paths.work_item_queries, current_user:)
          end

          post &::API::V3::Utilities::Endpoints::Create.new(model: WorkItemQuery).mount

          post :execute do
            status 200
            run_query(adhoc_query)
          end

          route_param :id, type: Integer do
            after_validation do
              @work_item_query = find_visible!
            end

            get do
              WorkItemQueryRepresenter.create(@work_item_query, current_user:, embed_links: true)
            end

            get :results do
              run_query(@work_item_query)
            end

            patch &::API::V3::Utilities::Endpoints::Update.new(model: WorkItemQuery).mount

            delete do
              raise ::API::Errors::Unauthorized unless @work_item_query.user_id == current_user.id

              @work_item_query.destroy!
              status 204
              body false
            end

            namespace :favorite do
              put do
                # create_or_find_by! (not find_or_create_by!) so concurrent PUTs hit the unique index and stay 204.
                WorkItemQueryFavorite.create_or_find_by!(user: current_user, work_item_query: @work_item_query)
                status 204
                body false
              rescue ActiveRecord::InvalidForeignKey # the query was deleted meanwhile
                raise ::API::Errors::NotFound
              end

              delete do
                WorkItemQueryFavorite.where(user: current_user, work_item_query: @work_item_query).delete_all
                status 204
                body false
              end
            end
          end
        end
      end
    end
  end
end
