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
require "rack/test"

RSpec.describe "API v3 work_item_queries" do
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:project) { create(:project) }
  shared_let(:status) { create(:status) }
  shared_let(:wp) { create(:work_package, project:, status:) }

  let(:permissions) { %i[view_work_packages save_queries] }
  let(:user) { create(:user, member_with_permissions: { project => permissions }) }
  let(:tree) { { op: "and", children: [{ field: "status", operator: "=", values: [status.id.to_s] }] } }
  let(:body) { JSON.parse(last_response.body) }

  before do
    login_as(user)
    header("Content-Type", "application/json")
  end

  def send_json(verb, path, payload) = public_send(verb, path, payload.to_json)

  def project_link(id) = { project: { href: id && api_v3_paths.project(id) } }

  def error_attributes
    errors = body["errorIdentifier"].end_with?("MultipleErrors") ? body.dig("_embedded", "errors") : [body]
    errors.map { it.dig("_embedded", "details", "attribute") }
  end

  describe "GET /api/v3/work_item_queries" do
    let(:owner) { create(:user) }
    let!(:mine) { create(:work_item_query, user:, project:, tree:, updated_by: owner) }
    let!(:pub) { create(:work_item_query, :public, user: owner, name: "A public") }

    before do
      create(:work_item_query, user: owner) # private, not listed
      create(:work_item_query, :public, user: owner, project: create(:project)) # project not visible
      WorkItemQueryFavorite.create!(user:, work_item_query: pub)
      get api_v3_paths.work_item_queries
    end

    it "returns a HAL collection of own and visible public queries without their trees" do
      expect(last_response).to have_http_status(200)
      expect(body).to include("_type" => "Collection", "total" => 2, "count" => 2)
      elements = body.dig("_embedded", "elements")
      expect(elements.pluck("id")).to eq [pub.id, mine.id] # ordered by name
      expect(elements).to all(include("_type" => "WorkItemQuery"))
      expect(elements.map { it.key?("tree") }).to eq [false, false]
      expect(elements.pluck("favorite")).to eq [true, false]

      element = elements.last
      expect(element).to include("name" => mine.name, "mode" => "flat", "public" => false,
                                 "columns" => %w[id type subject status assignee], "sortCriteria" => [%w[id asc]])
      expect(element["_links"]).to include(
        "self" => { "href" => api_v3_paths.work_item_query(mine.id), "title" => mine.name },
        "project" => { "href" => api_v3_paths.project(project.id), "title" => project.name },
        "user" => { "href" => api_v3_paths.user(user.id), "title" => user.name },
        "updatedBy" => { "href" => api_v3_paths.user(owner.id), "title" => owner.name }
      )
      expect(elements.first.dig("_links", "project")).to eq("href" => nil)
    end
  end

  describe "GET /api/v3/work_item_queries/:id" do
    it "returns the query with its tree" do
      query = create(:work_item_query, user:, tree:)
      get api_v3_paths.work_item_query(query.id)
      expect(last_response).to have_http_status(200)
      expect(body).to include("id" => query.id, "tree" => tree.as_json, "favorite" => false)
      expect(body).to include("createdAt", "updatedAt")
    end

    it "is 404 for another user's private query and a public one in a project the user cannot see" do
      [create(:work_item_query),
       create(:work_item_query, :public, project: create(:project))].each do |query|
        get api_v3_paths.work_item_query(query.id)
        expect(last_response).to have_http_status(404)
        get "#{api_v3_paths.work_item_query(query.id)}/results"
        expect(last_response).to have_http_status(404)
      end
    end
  end

  describe "POST /api/v3/work_item_queries" do
    it "creates a query from a camelCase body with a project link" do
      send_json :post, api_v3_paths.work_item_queries,
                { name: "Mine", mode: "tree", tree:, columns: %w[id subject], sortCriteria: [%w[subject desc]],
                  _links: project_link(project.id) }

      expect(last_response).to have_http_status(201)
      query = WorkItemQuery.find(body["id"])
      expect(query).to have_attributes(name: "Mine", mode: "tree", tree: tree.as_json, columns: %w[id subject],
                                       sort_criteria: [%w[subject desc]], project:, user:, updated_by: user)
      expect(body).to include("tree" => tree.as_json, "sortCriteria" => [%w[subject desc]])
    end

    it "applies the stored defaults and ignores read-only properties" do
      send_json :post, api_v3_paths.work_item_queries, { name: "x", id: 999, favorite: true }

      expect(last_response).to have_http_status(201)
      expect(body).to include("columns" => %w[id type subject status assignee], "sortCriteria" => [%w[id asc]],
                              "tree" => { "op" => "and", "children" => [] }, "public" => false, "favorite" => false)
      expect(body["id"]).not_to eq 999
      expect(body.dig("_links", "project", "href")).to be_nil
    end

    it "renders validation errors per attribute" do
      send_json :post, api_v3_paths.work_item_queries,
                { name: "", mode: "grid", public: nil, columns: "id", tree: { op: "xor", children: [] } }

      expect(last_response).to have_http_status(422)
      expect(body["errorIdentifier"]).to eq "urn:openproject-org:api:v3:errors:MultipleErrors"
      expect(error_attributes).to include("name", "mode", "public", "columns", "tree")
    end

    it "rejects a project the user cannot see as an error on project" do
      send_json :post, api_v3_paths.work_item_queries, { name: "x", _links: project_link(create(:project).id) }

      expect(last_response).to have_http_status(422)
      expect(body["errorIdentifier"]).to eq "urn:openproject-org:api:v3:errors:PropertyConstraintViolation"
      expect(error_attributes).to eq ["project"]
    end

    it "rejects public without manage_public_queries as an error on public" do
      send_json :post, api_v3_paths.work_item_queries, { name: "x", public: true }

      expect(last_response).to have_http_status(422)
      expect(error_attributes).to eq ["public"]
      expect(body["message"]).to eq "Sharing with everyone requires the permission to manage public queries."
    end

    context "without save_queries" do
      let(:permissions) { %i[view_work_packages] }

      it "is forbidden" do
        expect { send_json :post, api_v3_paths.work_item_queries, { name: "x" } }.not_to change(WorkItemQuery, :count)
        expect(last_response).to have_http_status(403)
      end
    end
  end

  describe "PATCH /api/v3/work_item_queries/:id" do
    let(:query) { create(:work_item_query, user:, project:) }

    it "updates the given properties and keeps the others" do
      send_json :patch, api_v3_paths.work_item_query(query.id), { name: "Renamed", tree:, _links: project_link(nil) }

      expect(last_response).to have_http_status(200)
      expect(query.reload).to have_attributes(name: "Renamed", tree: tree.as_json, project: nil, mode: "flat")
      expect(body).to include("name" => "Renamed", "tree" => tree.as_json)
    end

    it "is forbidden for a non-owner of a public query" do
      other = create(:work_item_query, :public, user: create(:user), project:)
      send_json :patch, api_v3_paths.work_item_query(other.id), { name: "hacked" }
      expect(last_response).to have_http_status(403)
      expect(other.reload.name).not_to eq "hacked"
    end

    it "is 404 for another user's private query" do
      send_json :patch, api_v3_paths.work_item_query(create(:work_item_query).id), { name: "hacked" }
      expect(last_response).to have_http_status(404)
    end

    it "rejects making it public without the permission as an error on public" do
      send_json :patch, api_v3_paths.work_item_query(query.id), { public: true }
      expect(last_response).to have_http_status(422)
      expect(error_attributes).to eq ["public"]
      expect(query.reload.public).to be false
    end

    it "rejects a malformed project link" do
      send_json :patch, api_v3_paths.work_item_query(query.id), { _links: { project: { href: "/api/v3/users/1" } } }
      expect(last_response).to have_http_status(422)
      expect(query.reload.project).to eq project
    end
  end

  describe "DELETE /api/v3/work_item_queries/:id" do
    it "deletes the owner's query" do
      query = create(:work_item_query, user:)
      delete api_v3_paths.work_item_query(query.id)
      expect(last_response).to have_http_status(204)
      expect(WorkItemQuery.exists?(query.id)).to be false
    end

    it "is forbidden for a non-owner of a public query" do
      other = create(:work_item_query, :public)
      delete api_v3_paths.work_item_query(other.id)
      expect(last_response).to have_http_status(403)
      expect(WorkItemQuery.exists?(other.id)).to be true
    end
  end

  describe "favorite" do
    let(:query) { create(:work_item_query, user:) }

    it "is idempotent on PUT and DELETE and shows up as favorite" do
      2.times do
        put "#{api_v3_paths.work_item_query(query.id)}/favorite"
        expect(last_response).to have_http_status(204)
      end
      get api_v3_paths.work_item_query(query.id)
      expect(body["favorite"]).to be true

      2.times do
        delete "#{api_v3_paths.work_item_query(query.id)}/favorite"
        expect(last_response).to have_http_status(204)
      end
      expect(WorkItemQueryFavorite.where(user:)).to be_empty
    end

    it "is 404 for an invisible query" do
      other = create(:work_item_query)
      put "#{api_v3_paths.work_item_query(other.id)}/favorite"
      expect(last_response).to have_http_status(404)
      delete "#{api_v3_paths.work_item_query(other.id)}/favorite"
      expect(last_response).to have_http_status(404)
    end
  end

  describe "POST /api/v3/work_item_queries/execute" do
    let(:path) { "#{api_v3_paths.work_item_queries}/execute" }

    it "runs an unsaved tree, persists nothing and honours pageSize" do
      create(:work_package, project:, status:)
      expect do
        send_json :post, path, { tree:, _links: project_link(project.id), pageSize: 1 }
      end.not_to change(WorkItemQuery, :count)

      expect(last_response).to have_http_status(200)
      expect(body["_type"]).to eq "Query"
      results = body.dig("_embedded", "results")
      expect(results["total"]).to eq 2
      expect(results.dig("_embedded", "elements").size).to eq 1
    end

    it "accepts the editor's column catalog" do
      catalog = %w[id type subject status assignee priority project author startDate dueDate percentageDone createdAt
                   updatedAt]
      send_json :post, path, { tree:, _links: project_link(project.id), columns: catalog }

      expect(last_response).to have_http_status(200)
      expect(body.dig("_links", "columns").map { it["href"].split("/").last }).to eq catalog
      expect(body.dig("_embedded", "results", "_embedded", "elements").pluck("id")).to contain_exactly(wp.id)
    end

    context "without save_queries" do
      let(:permissions) { %i[view_work_packages] }

      it "still runs" do
        send_json :post, path, { tree: }
        expect(last_response).to have_http_status(200)
      end
    end

    it "renders compiler errors as an error on tree" do
      send_json :post, path, { tree: { op: "or", children: [{ field: "nope", operator: "=", values: ["1"] }] } }

      expect(last_response).to have_http_status(422)
      expect(error_attributes).to eq ["tree"]
      expect(body["message"]).to eq I18n.t("work_item_queries.errors.invalid_condition", field: "nope")
    end

    it "renders validation errors and invisible projects as 422" do
      [{ mode: "grid" }, { columns: nil }, { sortCriteria: [%w[id up]] }, { _links: project_link(create(:project).id) }]
        .each do |bad|
        send_json :post, path, bad
        expect(last_response).to have_http_status(422)
      end
    end
  end

  describe "GET /api/v3/work_item_queries/:id/results" do
    let(:query) { create(:work_item_query, user:, project:, tree:) }

    it "runs the saved query with pageSize passthrough" do
      create(:work_package, project:, status:)
      get "#{api_v3_paths.work_item_query(query.id)}/results?pageSize=1"

      expect(last_response).to have_http_status(200)
      results = body.dig("_embedded", "results")
      expect(results["total"]).to eq 2
      expect(results.dig("_embedded", "elements").size).to eq 1
    end

    it "returns 422 for a stored tree the compiler rejects" do
      query.update_columns(tree: { "op" => "and",
                                   "children" => [{ "field" => "nope", "operator" => "=", "values" => ["1"] }] })
      get "#{api_v3_paths.work_item_query(query.id)}/results"
      expect(last_response).to have_http_status(422)
    end
  end

  context "with manage_public_queries in the project" do
    let(:permissions) { %i[view_work_packages save_queries manage_public_queries] }

    it "allows public queries in that project and globally" do
      send_json :post, api_v3_paths.work_item_queries, { name: "x", public: true, _links: project_link(project.id) }
      expect(last_response).to have_http_status(201)
      expect(body["public"]).to be true
      send_json :post, api_v3_paths.work_item_queries, { name: "y", public: true }
      expect(last_response).to have_http_status(201)
    end
  end

  it "rejects anonymous requests with 401 and creates nothing" do
    login_as(User.anonymous)
    expect { send_json :post, api_v3_paths.work_item_queries, { name: "x" } }.not_to change(WorkItemQuery, :count)
    expect(last_response).to have_http_status(401)
  end
end
