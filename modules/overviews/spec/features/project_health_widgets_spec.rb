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

require "spec_helper"

RSpec.describe "Project overview health and team widgets" do
  include TestSelectorFinders

  let(:project) { create(:project) }
  let(:status) { create(:status) }
  let(:member) { create(:user, firstname: "Dana", lastname: "Member", member_with_permissions: { project => permissions }) }
  let(:permissions) { %i[view_project view_work_packages view_members] }

  before do
    create(:work_package, project:, status:, assigned_to: member, due_date: Time.zone.today - 2)
    login_as member
    visit project_path(project)
  end

  it "shows computed health, key figures and every member's workload" do
    expect(page).to have_test_selector("project-health-risk")
    expect(page).to have_test_selector("project-kpi-overdue", text: "1")
    expect(page).to have_test_selector("team-progress-row", text: "Dana Member")
  end

  context "without permission to view members" do
    let(:permissions) { %i[view_project view_work_packages] }

    it "hides the team table but keeps the health figures" do
      expect(page).to have_test_selector("team-progress-no-permission")
      expect(page).to have_test_selector("project-kpi-open", text: "1")
    end
  end
end
