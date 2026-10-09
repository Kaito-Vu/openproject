# frozen_string_literal: true

# -- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2010-2024 the OpenProject GmbH
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
  class NewComponent < ApplicationComponent
    include ApplicationHelper
    include OpPrimer::ComponentHelpers
    include OpTurbo::Streamable
    include Projects::Concerns::IdentifierSuggestion

    options :project, :template, :step, :selected_variant_ids, :selected_module_names

    def step_2_display
      { display: :none } unless step == 2
    end

    def step_3_display
      { display: :none } unless step == 3
    end

    def step_4_display
      { display: :none } unless step == 4
    end

    # Always rendered (hidden outside step 3) so the choice survives the later steps.
    def modules_checkboxes
      safe_join(
        [hidden_field_tag("project[module_names][]", "", id: nil),
         tag.div(safe_join(project_modules.map { |name| module_checkbox(name) }), class: "op-project-type-grid")]
      )
    end

    def section_heading(key)
      tag.h3(I18n.t("create_project.#{key}"), class: "op-project-config-heading")
    end

    def types_checkboxes
      safe_join(
        [hidden_field_tag("project[variant_ids][]", "", id: nil),
         tag.div(safe_join(type_variants.map { |variant| type_checkbox(variant) }), class: "op-project-type-grid")]
      )
    end

    def workspaces_path
      workspace_type = if Project.workspace_types.key?(project.workspace_type)
                         project.workspace_type
                       else
                         "project"
                       end

      url_for(workspace_type.pluralize.to_sym)
    end

    private

    def type_variants
      TypeVariant.default_variant.includes(type: :color).sort_by { |variant| variant.type.position }
    end

    # nil = nothing submitted yet, so start from the types enabled for new projects
    def checked_variant_ids
      @checked_variant_ids ||= selected_variant_ids || TypeVariant.enabled_in_new_projects.ids
    end

    def project_modules
      OpenProject::AccessControl.available_project_modules(sorted: true)
    end

    def checked_module_names
      @checked_module_names ||= selected_module_names || Setting.default_projects_modules
    end

    def module_checkbox(name)
      tag.label(class: "op-project-type-card") do
        check_box_tag("project[module_names][]", name, checked_module_names.include?(name.to_s),
                      id: "project_module_names_#{name}", class: "FormControl-checkbox") +
          tag.span(l_or_humanize(name, prefix: "project_module_"), class: "op-project-type-card--name")
      end
    end

    def type_checkbox(variant)
      type = variant.type

      tag.label(class: "op-project-type-card") do
        check_box_tag("project[variant_ids][]", variant.id, checked_variant_ids.include?(variant.id),
                      id: "project_variant_ids_#{variant.id}", class: "FormControl-checkbox") +
          tag.span(class: "op-project-type-card--dot", style: ("--type-color: #{type.color.hexcode}" if type.color)) +
          tag.span(type.name, class: "op-project-type-card--name")
      end
    end
  end
end
