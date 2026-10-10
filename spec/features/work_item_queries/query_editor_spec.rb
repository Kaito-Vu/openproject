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

# UNRUN: needs a JS driver / browser, written against the data-test-selectors, labels and roles of the
# editor templates.
RSpec.describe "Query editor", :js do
  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:open_status) { create(:status, name: "Alpha open") }
  let(:closed_status) { create(:status, name: "Beta closed") }
  let!(:wp_open) { create(:work_package, project:, status: open_status, subject: "Open one") }
  let!(:wp_closed) { create(:work_package, project:, status: closed_status, subject: "Closed one") }

  let(:clause_rows) { "[data-test-selector='wiq-clause-row']" }

  before { login_as(user) }

  def pick_status(clause, status)
    within(clause) do
      # The field combobox opens on click (not on focus).
      find("input[role='combobox'][aria-label='#{I18n.t('js.work_item_queries.filter.field')}']").click
      find("li[role='option']", exact_text: I18n.t("js.work_packages.properties.status")).click
      # The value cell is a chip multi-select: open its dialog and tick the status.
      find("button[aria-haspopup='dialog']").click
      within("[role='dialog']") { check status.name }
    end
  end

  def name_and_save(name)
    find("input[aria-label='#{I18n.t('js.work_item_queries.editor.name_label')}']").set(name)
    click_on I18n.t("js.work_item_queries.editor.save")
  end

  it "runs and saves an OR query" do
    visit "/projects/#{project.identifier}/queries/editor"

    # The editor starts with one blank clause.
    pick_status(first(clause_rows), open_status)

    click_on I18n.t("js.work_item_queries.editor.add_new_clause")
    second = all(clause_rows).last
    within(second) do
      find(".wiq-andor select").find("option", text: I18n.t("js.work_item_queries.editor.or")).select_option
    end
    pick_status(second, closed_status)

    click_on I18n.t("js.work_item_queries.editor.run")
    expect(page).to have_link("Open one")
    expect(page).to have_link("Closed one", href: "/work_packages/#{wp_closed.id}")

    name_and_save("Both")
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)

    query = WorkItemQuery.find_by!(name: "Both")
    expect(query.tree["op"]).to eq "or"
    expect(query.tree["children"].size).to eq 2
    expect(query.tree.to_json).not_to include("key")
  end

  it "groups two selected clauses into an OR group, shows the group row and runs it" do
    visit "/projects/#{project.identifier}/queries/editor"

    pick_status(first(clause_rows), open_status)
    click_on I18n.t("js.work_item_queries.editor.add_new_clause")
    pick_status(all(clause_rows).last, closed_status)

    all(clause_rows).each { |row| within(row) { find(".wiq-pick input[type='checkbox']").check } }
    click_on I18n.t("js.label_group")
    expect(page).to have_css("[data-test-selector='wiq-group-row']", count: 1)
    within("[data-test-selector='wiq-group-row']") do
      expect(page).to have_button(I18n.t("js.work_item_queries.editor.ungroup"))
    end

    click_on I18n.t("js.work_item_queries.editor.run")
    expect(page).to have_text("Open one")
    expect(page).to have_text("Closed one")

    name_and_save("Grouped")
    expect(page).to have_current_path(/queries\/editor\?id=\d+/)
    group = WorkItemQuery.find_by!(name: "Grouped").tree["children"].first
    expect(group).to include("op" => "or")
    expect(group["children"].size).to eq 2
  end

  it "blocks running a clause without values and marks it" do
    visit "/projects/#{project.identifier}/queries/editor"
    within(first(clause_rows)) do
      find("input[role='combobox']").click
      # Type's first operator ("is") takes values; Status starts with "open", which does not.
      find("li[role='option']", exact_text: I18n.t("js.work_packages.properties.type")).click
    end

    click_on I18n.t("js.work_item_queries.editor.run")
    expect(page).to have_css(".flash-error", text: I18n.t("js.work_item_queries.errors.incomplete_clauses"))
    within(first(clause_rows)) do
      expect(page).to have_css("button[aria-invalid='true']")
      expect(page).to have_text(I18n.t("js.work_item_queries.errors.incomplete_clause"))
    end
  end

  it "renders parent and child nested in Tree mode" do
    create(:work_package, project:, status: open_status, subject: "Child one", parent: wp_open)
    visit "/projects/#{project.identifier}/queries/editor"

    click_on I18n.t("js.work_item_queries.editor.mode_tree")
    click_on I18n.t("js.work_item_queries.editor.run")

    expect(page).to have_css(".subject a", exact_text: "Open one")
    expect(page).to have_css(".subject[style*='padding-inline-start: 22px'] a", exact_text: "Child one")
  end

  it "shows a column picked in Column options" do
    type_label = I18n.t("js.work_packages.properties.type")
    priority_label = I18n.t("js.work_packages.properties.priority")
    visit "/projects/#{project.identifier}/queries/editor"
    click_on I18n.t("js.work_item_queries.editor.run")
    expect(page).to have_css("th", text: /\A#{type_label}\z/i)
    expect(page).to have_no_css("th", text: /\A#{priority_label}\z/i)

    click_on I18n.t("js.work_item_queries.editor.column_options")
    check priority_label
    uncheck type_label

    expect(page).to have_css("th", text: /\A#{priority_label}\z/i)
    expect(page).to have_no_css("th", text: /\A#{type_label}\z/i)
    expect(page).to have_css("td .chip-priority", exact_text: wp_open.priority.name)
    expect(page).to have_text(I18n.t("js.work_item_queries.editor.results_stale"))

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

  it "loads a saved query by id and reverts edits to it" do
    query = create(:work_item_query, user:, project:, name: "Saved one",
                                     tree: { op: "and", children: [{ field: "status", operator: "*", values: [] }] })
    visit "/projects/#{project.identifier}/queries/editor?id=#{query.id}"

    name_input = find("input[aria-label='#{I18n.t('js.work_item_queries.editor.name_label')}']")
    expect(name_input.value).to eq "Saved one"
    name_input.set("Changed")
    expect(page).to have_text(I18n.t("js.work_item_queries.editor.unsaved_changes"))

    accept_confirm { click_on I18n.t("js.work_item_queries.editor.revert") }
    expect(name_input.value).to eq "Saved one"
    expect(page).to have_no_text(I18n.t("js.work_item_queries.editor.unsaved_changes"))
  end
end
