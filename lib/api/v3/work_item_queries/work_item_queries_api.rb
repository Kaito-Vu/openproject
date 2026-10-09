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
        ATTRS = %i[name mode public project_id columns sort_criteria tree].freeze

        resources :work_item_queries do
          helpers ::API::V3::Queries::Helpers::QueryRepresenterResponse

          helpers do
            def item(record, favorite: record.favorite_of?(current_user))
              record.slice(:id, :name, :mode, :public, :project_id, :columns, :sort_criteria, :tree, :user_id)
                    .merge(favorite:,
                           updated_at: record.updated_at,
                           updated_by_name: (record.updated_by || record.user)&.name)
            end

            # Plain `params` slice: Grape `params do` blocks only bind to the next route,
            # so shared declarations would silently apply to just one verb.
            def attrs
              params.to_h.symbolize_keys.slice(*ATTRS).tap do |h|
                h[:tree] = JSON.parse(h[:tree].to_json) if h.key?(:tree)
                check_project!(h[:project_id])
              end
            end

            def check_project!(project_id)
              return if project_id.nil?

              render_invalid("Project not found") unless Project.visible(current_user).exists?(id: project_id)
            end

            def find_visible!
              WorkItemQuery.visible(current_user).find_by(id: params[:id]) || raise(::API::Errors::NotFound)
            end

            def find_owned!
              record = find_visible!
              raise ::API::Errors::Unauthorized unless record.user_id == current_user.id

              record
            end

            # Mirrors Queries::BaseContract#user_allowed_to_make_public: only flipping public on is checked,
            # so owners without the permission can still edit their already public queries.
            def check_public!(record)
              return unless record.public && record.public_changed?

              allowed = if record.project
                          current_user.allowed_in_project?(:manage_public_queries, record.project)
                        else
                          current_user.allowed_in_any_project?(:manage_public_queries)
                        end
              return if allowed

              raise ::API::Errors::Unauthorized.new(message: "Sharing a query with everyone requires the " \
                                                             "permission to manage public queries.")
            end

            def run_query(wiq)
              query = begin
                ::WorkItemQueries::BuildQuery.new(wiq, user: current_user).call
              rescue ::WorkItemQueries::Compiler::InvalidTree => e
                render_invalid(e.message)
              end
              query_representer_response(query, params.slice(:pageSize, :offset).to_h.symbolize_keys)
            end

            def error_text(record)
              record.errors.map { |e| "#{e.attribute} #{e.message}" }.to_sentence
            end

            def render_invalid(message)
              raise ::API::Errors::UnprocessableContent.new(message)
            end
          end

          # Authentication happens in after_validation, so authorize there too (a `before`
          # block would still see the anonymous user).
          after_validation do
            authorize_by_with_raise(current_user.logged?)
            authorize_in_any_work_package(:view_work_packages)
          end

          get do
            records = WorkItemQuery.visible(current_user).includes(:updated_by, :user).order(:name).to_a
            fav_ids = WorkItemQueryFavorite.where(user: current_user, work_item_query_id: records.map(&:id))
                                           .pluck(:work_item_query_id)
            { items: records.map { |r| item(r, favorite: fav_ids.include?(r.id)) } }
          end

          params do
            requires :name, type: String
          end
          post do
            record = WorkItemQuery.new(attrs.merge(user: current_user, updated_by: current_user))
            check_public!(record)
            if record.save
              status 201
              item(record)
            else
              render_invalid(error_text(record))
            end
          end

          post :execute do
            status 200
            wiq = WorkItemQuery.new(attrs.merge(name: "adhoc", user: current_user))
            render_invalid(error_text(wiq)) unless wiq.valid?
            run_query(wiq)
          end

          route_param :id, type: Integer do
            get { item(find_visible!) }

            get :results do
              run_query(find_visible!)
            end

            patch do
              record = find_owned!
              record.assign_attributes(attrs.merge(updated_by: current_user))
              check_public!(record)
              if record.save
                item(record)
              else
                render_invalid(error_text(record))
              end
            end

            delete do
              find_owned!.destroy!
              status 204
              body false
            end

            namespace :favorite do
              put do
                record = find_visible!
                # create_or_find_by! (not find_or_create_by!) so concurrent PUTs hit the unique index and stay 204.
                WorkItemQueryFavorite.create_or_find_by!(user: current_user, work_item_query: record)
                status 204
                body false
              end

              delete do
                WorkItemQueryFavorite.where(user: current_user, work_item_query_id: find_visible!.id).delete_all
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
