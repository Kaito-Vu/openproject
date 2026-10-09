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

module Projects
  # Numbered step indicator shown above the project creation wizard.
  class CreationStepperComponent < ApplicationComponent
    STEPS = %i[template details configuration attributes].freeze

    # Blank projects: template, details, configuration (types and modules)
    # (+ attributes when required fields exist).
    # Projects from a template only need template + details.
    def self.total_steps(project:, template:)
      return 2 if template

      project.available_custom_fields.for_all.required.any? ? 4 : 3
    end

    def initialize(current_step:, total_steps:)
      super()

      @current_step = current_step
      @total_steps = total_steps
    end

    def call
      tag.ol(class: "op-project-stepper", aria: { label: I18n.t("create_project.steps.label") }) do
        safe_join(STEPS.first(@total_steps).each_with_index.map { |key, index| step_item(key, index + 1) })
      end
    end

    private

    def step_item(key, number)
      tag.li(class: "op-project-stepper--item", data: { state: state_for(number) },
             aria: { current: (number == @current_step ? "step" : nil) }) do
        tag.span(number, class: "op-project-stepper--marker") +
          tag.span(I18n.t("create_project.steps.#{key}"), class: "op-project-stepper--label")
      end
    end

    def state_for(number)
      if number < @current_step
        "done"
      elsif number == @current_step
        "current"
      else
        "upcoming"
      end
    end
  end
end
