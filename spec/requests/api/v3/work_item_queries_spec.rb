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
require "rack/test"

RSpec.describe "API v3 work_item_queries" do
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:status) { create(:status) }
  let!(:wp) { create(:work_package, project:, status:) }
  let(:tree) { { op: "and", children: [{ field: "status", operator: "=", values: [status.id.to_s] }] } }

  before { login_as(user) }

  def post_json(path, body)
    header("Content-Type", "application/json")
    post(path, body.to_json)
  end

  def patch_json(path, body)
    header("Content-Type", "application/json")
    patch(path, body.to_json)
  end

  it "creates, lists, reads, updates and deletes" do
    post_json "/api/v3/work_item_queries", { name: "Mine", tree:, mode: "tree" }
    expect(last_response).to have_http_status(201)
    id = JSON.parse(last_response.body)["id"]

    get "/api/v3/work_item_queries"
    expect(JSON.parse(last_response.body)["items"].pluck("id")).to include(id)

    patch_json "/api/v3/work_item_queries/#{id}", { name: "Renamed" }
    expect(JSON.parse(last_response.body)["name"]).to eq "Renamed"

    delete "/api/v3/work_item_queries/#{id}"
    expect(last_response).to have_http_status(204)
    expect(WorkItemQuery.exists?(id)).to be false
  end

  it "rejects an invalid tree on create" do
    post_json "/api/v3/work_item_queries", { name: "x", tree: { op: "xor", children: [] } }
    expect(last_response).to have_http_status(422)
  end

  it "hides a private query of another user (404 on GET and PATCH)" do
    other = WorkItemQuery.create!(name: "o", user: create(:user))
    get "/api/v3/work_item_queries/#{other.id}"
    expect(last_response).to have_http_status(404)
    patch_json "/api/v3/work_item_queries/#{other.id}", { name: "hacked" }
    expect(last_response).to have_http_status(404)
  end

  it "rejects PATCH by a non-owner on a public query with 403" do
    other = WorkItemQuery.create!(name: "pub", public: true, user: create(:user))
    patch_json "/api/v3/work_item_queries/#{other.id}", { name: "hacked" }
    expect(last_response).to have_http_status(403)
    expect(other.reload.name).to eq "pub"
  end

  it "executes an unsaved tree and returns matching work packages" do
    post_json "/api/v3/work_item_queries/execute", { tree:, mode: "flat", project_id: project.id }
    expect(last_response).to have_http_status(200)
    ids = JSON.parse(last_response.body).dig("_embedded", "results", "_embedded", "elements").pluck("id")
    expect(ids).to contain_exactly(wp.id)
  end

  it "returns 422 when the tree uses an unsupported filter in OR" do
    bad = { op: "or", children: [{ field: "nope", operator: "=", values: ["1"] }] }
    post_json "/api/v3/work_item_queries/execute", { tree: bad }
    expect(last_response).to have_http_status(422)
    expect(JSON.parse(last_response.body)["message"]).to be_present
  end

  it "lists favorite flag and last modifier, and toggles favorites" do
    post_json "/api/v3/work_item_queries", { name: "Fav", tree: }
    id = JSON.parse(last_response.body)["id"]

    put "/api/v3/work_item_queries/#{id}/favorite"
    expect(last_response).to have_http_status(204)
    get "/api/v3/work_item_queries"
    item = JSON.parse(last_response.body)["items"].find { it["id"] == id }
    expect(item["favorite"]).to be true
    expect(item["updated_by_name"]).to eq user.name

    delete "/api/v3/work_item_queries/#{id}/favorite"
    get "/api/v3/work_item_queries"
    expect(JSON.parse(last_response.body)["items"].find { it["id"] == id }["favorite"]).to be false
  end

  describe "as a non-admin user" do
    let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
    let(:owner) { create(:user) }
    let!(:pub) { WorkItemQuery.create!(name: "pub", public: true, user: owner) }
    let!(:priv) { WorkItemQuery.create!(name: "priv", user: owner) }

    it "rejects DELETE by a non-owner on a public query with 403" do
      delete "/api/v3/work_item_queries/#{pub.id}"
      expect(last_response).to have_http_status(403)
      expect(WorkItemQuery.exists?(pub.id)).to be true
    end

    it "returns 404 for favorite PUT/DELETE on an invisible query" do
      header "Content-Type", "application/json"
      put "/api/v3/work_item_queries/#{priv.id}/favorite"
      expect(last_response).to have_http_status(404)
      delete "/api/v3/work_item_queries/#{priv.id}/favorite"
      expect(last_response).to have_http_status(404)
    end

    it "ignores a client-sent user_id on create" do
      post_json "/api/v3/work_item_queries", { name: "x", user_id: owner.id }
      expect(last_response).to have_http_status(201)
      expect(WorkItemQuery.find(JSON.parse(last_response.body)["id"]).user_id).to eq user.id
    end

    it "lists own and public queries but not other private ones" do
      mine = WorkItemQuery.create!(name: "mine", user:)
      get "/api/v3/work_item_queries"
      expect(JSON.parse(last_response.body)["items"].pluck("id")).to contain_exactly(pub.id, mine.id)
    end

    it "rejects invalid project_id with 422 on create, update and execute" do
      other_project = create(:project)
      [other_project.id, 0].each do |pid|
        post_json "/api/v3/work_item_queries", { name: "x", project_id: pid }
        expect(last_response).to have_http_status(422)
        post_json "/api/v3/work_item_queries/execute", { project_id: pid }
        expect(last_response).to have_http_status(422)
      end
      mine = WorkItemQuery.create!(name: "mine", user:)
      patch_json "/api/v3/work_item_queries/#{mine.id}", { project_id: other_project.id }
      expect(last_response).to have_http_status(422)
    end
  end

  it "rejects invalid columns, sort_criteria and null values with 422" do
    [{ columns: nil }, { columns: "id" }, { sort_criteria: nil }, { sort_criteria: [%w[id up]] }, { mode: "grid" }].each do |bad|
      post_json "/api/v3/work_item_queries", { name: "x" }.merge(bad)
      expect(last_response).to have_http_status(422)
      post_json "/api/v3/work_item_queries/execute", bad
      expect(last_response).to have_http_status(422)
    end
  end

  it "does not persist anything on execute and honours pageSize" do
    create(:work_package, project:, status:)
    expect do
      post_json "/api/v3/work_item_queries/execute", { tree:, project_id: project.id, pageSize: 1 }
    end.not_to change(WorkItemQuery, :count)
    expect(last_response).to have_http_status(200)
    expect(JSON.parse(last_response.body).dig("_embedded", "results", "_embedded", "elements").size).to eq 1
  end

  it "rejects anonymous requests and creates nothing" do
    login_as(User.anonymous)
    expect { post_json "/api/v3/work_item_queries", { name: "x" } }.not_to change(WorkItemQuery, :count)
    expect(last_response.status).to be_in([401, 403])
  end
end
