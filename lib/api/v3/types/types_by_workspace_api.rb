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
    module Types
      class TypesByWorkspaceAPI < ::API::OpenProjectAPI
        resources :types do
          after_validation do
            authorize_in_project %i[view_work_packages manage_types], project: @project
          end

          get do
            TypeCollectionRepresenter.new(@project.enabled_types,
                                          self_link: api_v3_paths.types_by_workspace(@project.id),
                                          current_user:)
          end

          # Replaces the project's types with the given set:
          # { "_links": { "types": [{ "href": "/api/v3/types/1" }, ...] } }
          # ponytail: enables each type's base variant; projects using a named variant keep it.
          put do
            ids = Array(params.dig(:_links, :types)).map do |link|
              ::API::Utilities::ResourceLinkParser.parse_id link["href"],
                                                            property: :type,
                                                            expected_version: "3",
                                                            expected_namespace: :types
            end.map(&:to_i).uniq

            types = Type.includes(:variants).where(id: ids).index_by(&:id)
            raise ::API::Errors::NotFound if types.size != ids.size

            current = @project.project_types.pluck(:type_id)
            services = { user: current_user, model: @project }

            (current - ids).each do |type_id|
              variant = @project.type_variant(Type.find(type_id))
              result = ::Projects::Types::RemoveService.new(**services).call(variant:)
              fail ::API::Errors::ErrorBase.create_and_merge_errors(result.errors) if result.failure?
            end

            (ids - current).each do |type_id|
              variant = types[type_id].default_variant
              result = ::Projects::Types::AddService.new(**services).call(variant:)
              fail ::API::Errors::ErrorBase.create_and_merge_errors(result.errors) if result.failure?
            end

            TypeCollectionRepresenter.new(@project.reload.enabled_types,
                                          self_link: api_v3_paths.types_by_workspace(@project.id),
                                          current_user:)
          end
        end
      end
    end
  end
end
