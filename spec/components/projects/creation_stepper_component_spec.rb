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

require "rails_helper"

RSpec.describe Projects::CreationStepperComponent, type: :component do
  subject(:rendered_component) { render_inline(described_class.new(current_step:, total_steps:)) }

  let(:total_steps) { 3 }

  context "on the second of three steps" do
    let(:current_step) { 2 }

    it "marks done, current and upcoming steps", :aggregate_failures do
      expect(rendered_component).to have_css "li[data-state='done']", text: "Template"
      expect(rendered_component).to have_css "li[data-state='current'][aria-current='step']", text: "Details"
      expect(rendered_component).to have_css "li[data-state='upcoming']", text: "Configuration"
      expect(rendered_component).to have_no_text "Attributes"
    end
  end

  context "with a required custom field step" do
    let(:total_steps) { 4 }
    let(:current_step) { 4 }

    it "shows the attributes step as current" do
      expect(rendered_component).to have_css "li[data-state='current']", text: "Attributes"
    end
  end

  describe ".total_steps" do
    let(:project) { Project.new }

    it "is 2 for a template and 3 for a blank project without required fields", :aggregate_failures do
      expect(described_class.total_steps(project:, template: build_stubbed(:template_project))).to eq 2
      expect(described_class.total_steps(project:, template: nil)).to eq 3
    end
  end
end
