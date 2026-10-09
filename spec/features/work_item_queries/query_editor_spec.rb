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

require "spec_helper"

# UNRUN: needs a JS driver / browser, written against the aria-labels of work-item-condition-row.
RSpec.describe "Query editor", :js do
  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:open_status) { create(:status, name: "Alpha open") }
  let(:closed_status) { create(:status, name: "Beta closed") }
  let!(:wp_open) { create(:work_package, project:, status: open_status, subject: "Open one") }
  let!(:wp_closed) { create(:work_package, project:, status: closed_status, subject: "Closed one") }

  before { login_as(user) }

  def pick_status(clause, status)
    within(clause) do
      find("select[aria-label='Field']").find("option", exact_text: "Status").select_option
      values = find("select[aria-label='Values for Status']")
      expect(values).to have_css("option", text: status.name)
      values.find("option", text: status.name).select_option
    end
  end

  it "runs and saves an OR query" do
    visit "/projects/#{project.identifier}/queries/editor"

    click_on "Add new clause"
    pick_status(first(".op-wiq-row"), open_status)

    click_on "Add new clause"
    second = all(".op-wiq-row").last
    within(second) { find("select[aria-label='Operator for clause']").find("option", text: "Or").select_option }
    pick_status(second, closed_status)

    click_on "Run query"
    expect(page).to have_text("Open one")
    expect(page).to have_text("Closed one")

    accept_prompt(with: "Both") { click_on "Save query" }
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)

    query = WorkItemQuery.find_by!(name: "Both")
    expect(query.tree["op"]).to eq "or"
    expect(query.tree["children"].size).to eq 2
  end
end
