# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require_relative "../../../support/query_counter"

RSpec.describe "API v3 issue view" do # rubocop:disable RSpec/DescribeClass
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:type) { create(:type) }
  shared_let(:project) { create(:project, types: [type]) }
  shared_let(:work_package) { create(:work_package, project:, type:, subject: "Login fails") }
  shared_let(:admin) { create(:admin) }
  shared_let(:viewer) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:editor) do
    create(:user, member_with_permissions: { project => %i[view_work_packages edit_work_packages add_work_package_comments] })
  end
  shared_let(:outsider) { create(:user) }

  def json = JSON.parse(last_response.body)

  def view_path(id = work_package.id) = api_v3_paths.work_package_issue_view(id)

  describe "GET issue_view" do
    it "returns the contract for an editor" do
      login_as(editor)
      get view_path

      expect(last_response).to have_http_status(:ok)
      expect(json).to include("_type" => "IssueView", "id" => work_package.id, "subject" => "Login fails",
                              "identifier" => work_package.display_id, "lockVersion" => work_package.lock_version)
      expect(json["header"].keys).to match_array(%w[type status priority assignee author])
      expect(json["permissions"].keys).to match_array(%w[view edit delete comment transition addRelation
                                                         manageWatchers addAttachment logTime])
      expect(json["permissions"]).to include("view" => true, "edit" => true, "comment" => true, "delete" => false)
      expect(json["source"]).to be_in(%w[screen native])
      expect(json["counts"]).to include("comments", "children", "relations")
      expect(json["_links"]).to include("self", "workPackage", "activities", "updateImmediately", "addComment")
    end

    it "reports no edit rights and hides write links for a viewer" do
      login_as(viewer)
      get view_path

      expect(last_response).to have_http_status(:ok)
      expect(json["permissions"]).to include("edit" => false, "comment" => false)
      expect(json["_links"]).not_to include("updateImmediately", "addComment")
      fields = json["sections"].flat_map { |section| section["fields"] }
      expect(fields).to all(include("editable" => false, "editableReason" => "no_permission"))
    end

    it "exposes diagnostics only to admins" do
      login_as(admin)
      get view_path
      expect(json).to have_key("diagnostics")

      login_as(editor)
      get view_path
      expect(json).not_to have_key("diagnostics")
    end

    it "sends private cache headers and no ETag" do
      login_as(editor)
      get view_path

      expect(last_response.headers["Cache-Control"]).to include("private")
      expect(last_response.headers["Vary"]).to include("Authorization")
      expect(last_response.headers).not_to have_key("ETag")
    end

    it "hides parent title when the parent is not visible" do
      other_project = create(:project, types: [type])
      parent = create(:work_package, project: other_project, type:)
      child = create(:work_package, project:, type:, parent:)
      login_as(editor)
      get view_path(child.id)

      expect(last_response).to have_http_status(:ok)
      expect(json["parent"]).to be_nil
    end

    it "does not increase the query count with the number of custom fields" do
      login_as(editor)
      get view_path
      few = IssueViewQueryCounter.count { get view_path }

      create_list(:work_package_custom_field, 10, types: [type], projects: [project], is_for_all: true)
      many = IssueViewQueryCounter.count { get view_path(create(:work_package, project:, type:).id) }

      expect(many).to be <= few + 5
    end
  end

  describe "authorization" do
    it "returns 404 for a user who cannot see the work package" do
      login_as(outsider)
      get view_path
      expect(last_response).to have_http_status(:not_found)
    end

    it "returns 404 for a missing id" do
      login_as(editor)
      get view_path(0)
      expect(last_response).to have_http_status(:not_found)
    end

    it "returns 404 for an archived project" do
      archived = create(:project, :archived, types: [type])
      wp = create(:work_package, project: archived, type:)
      login_as(admin)
      get view_path(wp.id)
      expect(last_response).to have_http_status(:not_found)
    end

    it "never answers 403", :aggregate_failures do
      [viewer, outsider, editor].each do |user|
        login_as(user)
        get view_path
        expect(last_response.status).not_to eq(403)
      end
    end
  end

  describe "route table" do
    it "only registers GET routes for issue_view" do
      routes = API::V3::Root.routes.select { |route| route.path.include?("issue_view") }
      expect(routes).not_to be_empty
      expect(routes.map(&:request_method).uniq).to eq(["GET"])
    end
  end
end
