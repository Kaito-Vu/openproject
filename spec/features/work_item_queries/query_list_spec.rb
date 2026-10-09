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

require "spec_helper"

RSpec.describe "Queries list", :js do
  let(:user) { create(:admin) }
  let(:other) { create(:user) }
  let!(:mine) { WorkItemQuery.create!(name: "My bugs", user:, updated_by: user) }
  let!(:shared) { WorkItemQuery.create!(name: "Release bugs", user: other, updated_by: other, public: true) }
  let!(:private_other) { WorkItemQuery.create!(name: "Hidden", user: other) }

  before { login_as(user) }

  it "shows My and Shared sections, favorites tab and keyword filter" do
    visit "/queries"
    expect(page).to have_text("My bugs")
    expect(page).to have_text("Release bugs")
    expect(page).to have_no_text("Hidden")

    fill_in "Filter by keywords", with: "release"
    expect(page).to have_no_text("My bugs")

    fill_in "Filter by keywords", with: ""
    within(:xpath, "//tr[contains(., 'My bugs')]") { find("button[aria-pressed]").click }
    click_on "Favorites"
    expect(page).to have_text("My bugs")
    expect(page).to have_no_text("Release bugs")
  end

  it "opens the editor from New query" do
    visit "/queries"
    click_on "New query"
    expect(page).to have_current_path(%r{/queries/editor})
  end
end
