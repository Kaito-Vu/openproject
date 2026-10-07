# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "API v3 issue view activities" do # rubocop:disable RSpec/DescribeClass
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:type) { create(:type) }
  shared_let(:project) { create(:project, types: [type]) }
  shared_let(:author) { create(:user, member_with_permissions: { project => %i[view_work_packages edit_work_packages] }) }
  shared_let(:viewer) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:outsider) { create(:user) }

  let(:work_package) { create(:work_package, project:, type:, author:) }

  def json = JSON.parse(last_response.body)

  def activities_path = api_v3_paths.work_package_issue_view_activities(work_package.id)

  def comment!(text, user: author)
    work_package.add_journal(user:, notes: text)
    work_package.save!(validate: false)
  end

  def events = json.dig("_embedded", "elements")

  before { login_as(viewer) }

  it "returns a collection envelope with COMMENT events" do
    comment!("first")
    get activities_path

    expect(last_response).to have_http_status(:ok)
    expect(json).to include("_type" => "Collection", "pageSize" => 20, "offset" => 1)
    comment = events.find { |event| event["type"] == "COMMENT" }
    expect(comment["id"]).to end_with(":comment")
    expect(comment["comment"]["body"]["raw"]).to eq("first")
    expect(comment["actor"]).to include("id" => author.id)
  end

  it "splits one journal into a comment event and detail events" do
    work_package.add_journal(user: author, notes: "note")
    work_package.subject = "Changed"
    work_package.save!(validate: false)
    get activities_path

    ids = events.map { |event| event["id"] }
    journal_id = work_package.journals.last.id
    expect(ids).to include("#{journal_id}:comment", "#{journal_id}:0")
    expect(events.find { |event| event["id"] == "#{journal_id}:0" })
      .to include("type" => "FIELD_CHANGED", "field" => "subject")
  end

  it "filters by type" do
    comment!("x")
    get activities_path, filters: [{ type: { operator: "=", values: ["COMMENT"] } }].to_json

    expect(last_response).to have_http_status(:ok)
    expect(events.map { |event| event["type"] }.uniq).to eq(["COMMENT"])
  end

  it "paginates by journal and clamps pageSize" do
    3.times { |i| comment!("c#{i}") }
    get activities_path, pageSize: "1000"
    expect(json["pageSize"]).to eq([100, Setting.apiv3_max_page_size].min)

    get activities_path, pageSize: "0"
    expect(events).to eq([])
    expect(json["total"]).to be >= 3
  end

  it "treats a bad offset as page one" do
    get activities_path, offset: "abc"
    expect(last_response).to have_http_status(:ok)
    expect(json["offset"]).to eq(1)
  end

  describe "invalid parameters" do
    it "rejects a negative pageSize with 400" do
      get activities_path, pageSize: "-5"
      expect(last_response).to have_http_status(:bad_request)
    end

    it "rejects malformed JSON in filters and sortBy with 400, not 500" do
      get activities_path, filters: "abc"
      expect(last_response).to have_http_status(:bad_request)

      get activities_path, sortBy: "abc"
      expect(last_response).to have_http_status(:bad_request)
    end

    it "rejects unknown sort keys and filter types with 400" do
      get activities_path, sortBy: [["createdAt", "asc"]].to_json
      expect(last_response).to have_http_status(:bad_request)

      get activities_path, filters: [{ type: { operator: "=", values: ["NOPE"] } }].to_json
      expect(last_response).to have_http_status(:bad_request)
    end
  end

  describe "visibility" do
    it "returns 404 for users who cannot see the work package" do
      login_as(outsider)
      get activities_path
      expect(last_response).to have_http_status(:not_found)
    end

    it "does not expose internal comments to users without the permission" do
      work_package.add_journal(user: author, notes: "secret", internal: true)
      work_package.save!(validate: false)
      get activities_path

      expect(events.map { |event| event.dig("comment", "body", "raw") }).not_to include("secret")
    end
  end
end
