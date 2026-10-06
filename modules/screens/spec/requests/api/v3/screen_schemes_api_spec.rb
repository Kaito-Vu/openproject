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

RSpec.describe "API v3 screen schemes" do # rubocop:disable RSpec/DescribeClass
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:admin) { create(:admin) }
  shared_let(:project) { create(:project) }
  shared_let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:outsider) { create(:user) }
  shared_let(:type) { create(:type) }
  shared_let(:scheme) { create(:screen_scheme, name: "Dev") }
  shared_let(:create_screen) { create(:create_screen) }

  let(:json) { JSON.parse(last_response.body) }
  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  it "lets a user read schemes assigned to a project they can view" do
    create(:project_screen_scheme, project:, scheme:)
    login_as(user)
    get api_v3_paths.screen_schemes
    expect(last_response).to have_http_status(:ok)
    expect(json["_embedded"]["elements"].pluck("name")).to include("Dev")
    get api_v3_paths.screen_scheme(scheme.id)
    expect(last_response).to have_http_status(:ok)
  end

  it "hides schemes from users without view permission (empty list, 404 on show) and anonymous gets 401" do
    create(:project_screen_scheme, project:, scheme:)
    login_as(outsider)
    get api_v3_paths.screen_schemes
    expect(json["_embedded"]["elements"]).to be_empty
    get api_v3_paths.screen_scheme(scheme.id)
    expect(last_response).to have_http_status(:not_found)

    logout
    get api_v3_paths.screen_schemes
    expect(last_response).to have_http_status(:unauthorized)
  end

  it "activates and deactivates as administrator only" do
    login_as(user)
    post "#{api_v3_paths.screen_scheme(scheme.id)}/deactivate", nil, headers
    expect(last_response).to have_http_status(:forbidden)

    login_as(admin)
    post "#{api_v3_paths.screen_scheme(scheme.id)}/deactivate", nil, headers
    expect(last_response).to have_http_status(:ok)
    expect(scheme.reload.active).to be(false)
    post "#{api_v3_paths.screen_scheme(scheme.id)}/activate", nil, headers
    expect(scheme.reload.active).to be(true)
  end

  it "rejects a scheme update that breaks required coverage for a using project" do
    used_type = create(:type)
    used = create(:screen_scheme, name: "Used")
    create(:project_screen_scheme, project: create(:project, types: [used_type]), scheme: used)
    login_as(admin)
    patch api_v3_paths.screen_scheme(used.id),
          { typeItems: [{ typeId: used_type.id, createScreen: create_screen.id }] }.to_json, headers
    expect(last_response).to have_http_status(:unprocessable_entity)
    expect(used.reload.items).to be_empty
  end

  it "forbids writes for non administrators" do
    login_as(user)
    post api_v3_paths.screen_schemes, { name: "X" }.to_json, headers
    expect(last_response).to have_http_status(:forbidden)
  end

  it "creates a scheme with type items as administrator" do
    login_as(admin)
    body = { name: "New", typeItems: [{ typeId: type.id, createScreen: create_screen.id }] }
    post api_v3_paths.screen_schemes, body.to_json, headers
    expect(last_response).to have_http_status(:created)
    expect(json["typeItems"].first.dig("_links", "createScreen", "href")).to be_present
  end
end
