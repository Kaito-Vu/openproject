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

RSpec.describe "Homescreen", "index" do
  let(:user) { build_stubbed(:user) }

  it "is reachable by the global menu" do
    login_as user
    visit root_url

    within "#main-menu" do
      click_on "Home"
    end

    expect(page).to have_current_path(home_path)
  end

  describe "dashboard" do
    let(:project) { create(:project) }
    let(:member) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
    let!(:overdue) do
      create(:work_package, project:, assigned_to: member, due_date: Time.zone.today - 3, subject: "Late one")
    end

    before do
      login_as member
      visit root_url
    end

    it "shows the overview cards, the user's deadlines and the project progress" do
      expect(page).to have_test_selector("dashboard-kpi-overdue", text: "1")
      expect(page).to have_test_selector("my-work-overdue", text: "Late one")
      expect(page).to have_test_selector("portfolio-health-row", text: project.name)
      expect(page).to have_test_selector("status-distribution-row")
    end
  end

  describe "Impressum (legal notice) link" do
    before do
      OpenProject::Static::Links.reset_cache
      login_as user
      visit root_url
    end

    after do
      OpenProject::Static::Links.reset_cache
    end

    context "when impressum_link is set",
            with_config: { impressum_link: "https://example.com/impressum/" } do
      it "renders the correct link" do
        expect(page).to have_link(I18n.t("homescreen.links.impressum"),
                                  href: OpenProject::Static::Links.url_for(:impressum))
      end
    end

    context "when impressum_link is not set",
            with_config: { impressum_link: nil } do
      it "does not render the 'Legal notice' link" do
        # Wait for page load before checking absence of impressum link
        expect(page).to have_link(I18n.t("homescreen.links.blog"),
                                  href: OpenProject::Static::Links.url_for(:blog))

        expect(page).to have_no_link(I18n.t("homescreen.links.impressum"))
      end
    end
  end
end
