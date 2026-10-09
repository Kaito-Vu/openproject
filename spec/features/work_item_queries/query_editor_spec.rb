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

# UNRUN: needs a JS driver / browser, written against the labels and aria-labels of the editor templates.
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
      find("input[aria-label='#{I18n.t('js.work_item_queries.filter.field')}']").click
      find("li[role='option']", exact_text: I18n.t("js.work_packages.properties.status")).click
      # The value cell is a chip multi-select: open it, tick the status in the popover.
      find("[role='combobox'][aria-label='#{I18n.t('js.work_item_queries.filter.values_for', field: 'Status')}']").click
      find("[role='option']", text: status.name).find("input[type='checkbox']").check
    end
  end

  def name_and_save(name)
    find("input[aria-label='#{I18n.t('js.work_item_queries.editor.name_label')}']").set(name)
    click_on I18n.t("js.work_item_queries.editor.save")
  end

  it "runs and saves an OR query" do
    visit "/projects/#{project.identifier}/queries/editor"

    # The editor starts with one blank clause.
    pick_status(first(".wiq-row"), open_status)

    click_on I18n.t("js.work_item_queries.editor.add_new_clause")
    second = all(".wiq-row").last
    within(second) do
      find("select[aria-label='#{I18n.t('js.work_item_queries.editor.clause_operator')}']")
        .find("option", text: I18n.t("js.work_item_queries.editor.or")).select_option
    end
    pick_status(second, closed_status)

    click_on I18n.t("js.work_item_queries.editor.run")
    expect(page).to have_text("Open one")
    expect(page).to have_text("Closed one")

    name_and_save("Both")
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)

    query = WorkItemQuery.find_by!(name: "Both")
    expect(query.tree["op"]).to eq "or"
    expect(query.tree["children"].size).to eq 2
  end

  it "groups two selected clauses into an OR group and runs it" do
    visit "/projects/#{project.identifier}/queries/editor"

    pick_status(first(".wiq-row"), open_status)
    click_on I18n.t("js.work_item_queries.editor.add_new_clause")
    pick_status(all(".wiq-row").last, closed_status)

    select_clause = "input[aria-label='#{I18n.t('js.work_item_queries.editor.select_clause')}']"
    all(".wiq-row").each { |row| within(row) { find(select_clause).check } }
    click_on I18n.t("js.label_group")
    expect(page).to have_button(I18n.t("js.work_item_queries.editor.ungroup"), count: 2)

    click_on I18n.t("js.work_item_queries.editor.run")
    expect(page).to have_text("Open one")
    expect(page).to have_text("Closed one")

    name_and_save("Grouped")
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)
    group = WorkItemQuery.find_by!(name: "Grouped").tree["children"].first
    expect(group).to include("op" => "or")
    expect(group["children"].size).to eq 2
  end

  it "renders parent and child nested in Tree mode" do
    create(:work_package, project:, status: open_status, subject: "Child one", parent: wp_open)
    visit "/projects/#{project.identifier}/queries/editor"

    click_on I18n.t("js.work_item_queries.editor.mode_tree")
    click_on I18n.t("js.work_item_queries.editor.run")

    expect(page).to have_css(".subject", exact_text: "Open one")
    expect(page).to have_css(".subject[style*='padding-left: 22px']", exact_text: "Child one")
  end

  it "shows a column picked in Column options" do
    type_label = I18n.t("js.work_packages.properties.type")
    priority_label = I18n.t("js.work_packages.properties.priority")
    visit "/projects/#{project.identifier}/queries/editor"
    click_on I18n.t("js.work_item_queries.editor.run")
    # Header cells are upper-cased by CSS, so match case-insensitively.
    expect(page).to have_css("th", text: /\A#{type_label}\z/i)
    expect(page).to have_no_css("th", text: /\A#{priority_label}\z/i)

    click_on I18n.t("js.work_item_queries.editor.column_options")
    check priority_label
    uncheck type_label

    expect(page).to have_css("th", text: /\A#{priority_label}\z/i)
    expect(page).to have_no_css("th", text: /\A#{type_label}\z/i)
    expect(page).to have_css("td .chip-priority", exact_text: wp_open.priority.name)

    name_and_save("With priority")
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)
    expect(WorkItemQuery.find_by!(name: "With priority").columns).to eq %w[id subject status assignee priority]
  end

  it "lets an admin share a query with everyone" do
    visit "/projects/#{project.identifier}/queries/editor"

    check I18n.t("js.work_item_queries.editor.shared_with_everyone")
    name_and_save("Shared")
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)

    expect(WorkItemQuery.find_by!(name: "Shared")).to have_attributes(public: true, project_id: project.id)
  end
end
