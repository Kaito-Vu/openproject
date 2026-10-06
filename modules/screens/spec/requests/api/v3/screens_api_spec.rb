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
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "API v3 screens" do # rubocop:disable RSpec/DescribeClass
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:admin) { create(:admin) }
  shared_let(:project) { create(:project) }
  shared_let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:outsider) { create(:user) }
  shared_let(:screen) { create(:create_screen, name: "Bug create") }

  def json = JSON.parse(last_response.body)

  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  describe "read" do
    before do
      create(:screen_scheme_item, scheme: create(:project_screen_scheme, project:).scheme, create_screen: screen)
    end

    it "lets a user list and read screens used by a scheme of a project they can view" do
      login_as(user)
      get api_v3_paths.screens
      expect(last_response).to have_http_status(:ok)
      expect(json["_embedded"]["elements"].pluck("name")).to include("Bug create")

      get api_v3_paths.screen(screen.id)
      expect(last_response).to have_http_status(:ok)
      expect(last_response.headers["ETag"]).to be_present
      expect(json["screenType"]).to eq("create")
    end

    it "answers 401 for anonymous users" do
      get api_v3_paths.screens
      expect(last_response).to have_http_status(:unauthorized)
    end

    it "hides screens from a user without view permission (empty list, 404 on show)" do
      login_as(outsider)
      get api_v3_paths.screens
      expect(last_response).to have_http_status(:ok)
      expect(json["_embedded"]["elements"]).to be_empty
      get api_v3_paths.screen(screen.id)
      expect(last_response).to have_http_status(:not_found)
    end

    it "hides screens that no visible scheme uses" do
      lonely = create(:create_screen, name: "Unused")
      login_as(user)
      get api_v3_paths.screen(lonely.id)
      expect(last_response).to have_http_status(:not_found)
    end

    it "lets an administrator read" do
      login_as(admin)
      get api_v3_paths.screens
      expect(last_response).to have_http_status(:ok)
    end
  end

  describe "write" do
    it "forbids non administrators" do
      login_as(user)
      post api_v3_paths.screens, { name: "X", screenType: "create" }.to_json, headers
      expect(last_response).to have_http_status(:forbidden)
    end

    it "creates and updates as administrator" do
      login_as(admin)
      post api_v3_paths.screens, { name: "View screen", screenType: "view" }.to_json, headers
      expect(last_response).to have_http_status(:created)
      id = json["id"]

      patch api_v3_paths.screen(id), { name: "Renamed" }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(json["name"]).to eq("Renamed")
    end

    it "treats screenType as read-only" do
      login_as(admin)
      patch api_v3_paths.screen(screen.id), { screenType: "edit" }.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
      expect(json["errorIdentifier"]).to include("PropertyIsReadOnly")
    end

    it "requires If-Match for the layout endpoint" do
      login_as(admin)
      put api_v3_paths.screen_layout(screen.id), { sections: [] }.to_json, headers
      expect(last_response).to have_http_status(428)
    end

    it "rejects a stale If-Match with UpdateConflict" do
      login_as(admin)
      header "If-Match", "stale"
      put api_v3_paths.screen_layout(screen.id), { sections: [] }.to_json, headers
      expect(last_response).to have_http_status(:conflict)
    end
  end

  describe "activate and deactivate" do
    it "toggles the screen as administrator" do
      login_as(admin)
      post "#{api_v3_paths.screen(screen.id)}/deactivate", nil, headers
      expect(last_response).to have_http_status(:ok)
      expect(screen.reload.active).to be(false)

      post "#{api_v3_paths.screen(screen.id)}/activate", nil, headers
      expect(screen.reload.active).to be(true)
    end

    it "forbids non administrators" do
      login_as(user)
      post "#{api_v3_paths.screen(screen.id)}/deactivate", nil, headers
      expect(last_response).to have_http_status(:forbidden)
    end
  end

  describe "partial section and item edits" do
    shared_let(:edit_screen) { create(:create_screen, name: "Editable") }
    shared_let(:section) { create(:screen_section, screen: edit_screen, name: "General", position: 1) }
    shared_let(:subject_item) { create(:screen_item, screen: edit_screen, section:, field_key: "subject", position: 1) }
    shared_let(:priority_item) { create(:screen_item, screen: edit_screen, section:, field_key: "priority", position: 2) }
    shared_let(:other_section) { create(:screen_section, screen: edit_screen, name: "More", position: 2) }

    let(:base) { api_v3_paths.screen(edit_screen.id) }

    before { login_as(admin) }

    context "when the screen is in use by a scheme" do
      before { create(:screen_scheme_item, create_screen: edit_screen) }

      it "refuses to delete the subject item (same coverage as PUT layout)" do
        delete "#{base}/items/#{subject_item.id}"
        expect(last_response).to have_http_status(:unprocessable_entity)
        expect(ScreenItem.exists?(subject_item.id)).to be(true)
      end

      it "refuses to hide the subject item" do
        patch "#{base}/items/#{subject_item.id}", { visible: false }.to_json, headers
        expect(last_response).to have_http_status(:unprocessable_entity)
        expect(subject_item.reload.visible).to be(true)
      end

      it "refuses to delete the section holding the subject item" do
        delete "#{base}/sections/#{section.id}"
        expect(last_response).to have_http_status(:unprocessable_entity)
        expect(ScreenSection.exists?(section.id)).to be(true)
      end

      it "allows harmless edits" do
        patch "#{base}/items/#{priority_item.id}", { visible: false }.to_json, headers
        expect(last_response).to have_http_status(:ok)
      end
    end

    it "keeps the order when a partial item edit sends no position, even for a stored position of 0" do
      priority_item.update_column(:position, 0)
      patch "#{base}/items/#{priority_item.id}", { visible: false }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(section.items.reload.order(:position).pluck(:field_key)).to eq(%w[priority subject])
    end

    it "renumbers siblings when an item changes position" do
      patch "#{base}/items/#{priority_item.id}", { position: 1 }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(section.items.reload.order(:position).pluck(:field_key)).to eq(%w[priority subject])
      expect(section.items.pluck(:position).sort).to eq([1, 2])
    end

    it "renumbers both sections when an item moves between sections" do
      patch "#{base}/items/#{subject_item.id}", { sectionId: other_section.id, position: 1 }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(section.items.reload.pluck(:field_key, :position)).to eq([["priority", 1]])
      expect(other_section.items.reload.pluck(:field_key, :position)).to eq([["subject", 1]])
    end

    it "closes the gap after deleting an item" do
      delete "#{base}/items/#{subject_item.id}"
      expect(last_response).to have_http_status(:no_content)
      expect(priority_item.reload.position).to eq(1)
    end

    it "renumbers sections on move and delete" do
      patch "#{base}/sections/#{other_section.id}", { position: 1 }.to_json, headers
      expect(edit_screen.sections.reload.map(&:name)).to eq(%w[More General])
      delete "#{base}/sections/#{other_section.id}"
      expect(section.reload.position).to eq(1)
    end

    it "changes the ETag so a stale If-Match on PUT layout is detected after a partial edit" do
      get base
      stale = last_response.headers["ETag"]
      travel_to(1.minute.from_now) do
        patch "#{base}/items/#{priority_item.id}", { width: "half" }.to_json, headers
      end
      get base
      expect(last_response.headers["ETag"]).to be_present
      expect(last_response.headers["ETag"]).not_to eq(stale)

      header "If-Match", stale
      put "#{base}/layout", { sections: [] }.to_json, headers
      expect(last_response).to have_http_status(:conflict)
    end

    it "adds a non-blocking hidden_but_placed warning to the editor response" do
      allow(::Screens::CoverageValidation).to receive(:hidden_but_placed).and_return(["priority"])
      patch "#{base}/items/#{priority_item.id}", { width: "half" }.to_json, headers
      expect(json["warnings"]).to include({ "code" => "hidden_but_placed", "fields" => ["priority"] })
    end
  end
end
