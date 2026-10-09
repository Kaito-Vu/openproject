# frozen_string_literal: true

# -- copyright
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
# ++
module Projects
  module Settings
    # Optional wizard field: who receives the default project admin role in the new project.
    class ProjectAdminForm < ApplicationForm
      form do |f|
        f.autocompleter(
          name: :project_admin_id,
          label: I18n.t("create_project.project_admin_label"),
          caption: I18n.t("create_project.project_admin_caption"),
          autocomplete_options: {
            component: "opce-user-autocompleter",
            allowEmpty: true,
            defaultData: false,
            focusDirectly: false,
            model: selected_admin_model,
            placeholder: I18n.t(:label_user_search),
            url: ::API::V3::Utilities::PathHelper::ApiV3Path.principals,
            resource: "principals",
            searchKey: "any_name_attribute",
            filters: [{ name: "type", operator: "=", values: %w[User] },
                      { name: "status", operator: "=", values: [Principal.statuses[:active].to_s] }]
          }
        )
      end

      private

      def selected_admin_model
        admin = User.active.find_by(id: model.project_admin_id.presence)
        { id: admin.id, name: admin.name } if admin
      end
    end
  end
end
