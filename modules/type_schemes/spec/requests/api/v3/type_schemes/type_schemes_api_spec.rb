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

RSpec.describe "API v3 type schemes" do
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:epic) { create(:type, name: "Epic") }
  shared_let(:story) { create(:type, name: "Story") }
  shared_let(:bug) { create(:type, name: "Bug") }
  shared_let(:project) { create(:project, types: [epic, story, bug]) }
  shared_let(:admin) { create(:admin) }
  shared_let(:member) do
    create(:user, member_with_permissions: { project => %i[view_work_packages assign_type_scheme] })
  end
  shared_let(:viewer) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:scheme) { create(:type_scheme, name: "Dev", types: [story, epic]) }

  let(:json) { JSON.parse(last_response.body) }
  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  def body_for(name, types)
    { name:,
      typeItems: types.each_with_index.map do |type, i|
        { _links: { type: { href: api_v3_paths.type(type.id) } }, position: i + 1, default: i.zero? }
      end }.to_json
  end

  describe "reading" do
    before do
      TypeSchemes::SchemeService.assign(project, scheme)
      login_as(viewer)
    end

    it "lists schemes" do
      get api_v3_paths.type_schemes
      expect(last_response).to have_http_status(:ok)
      expect(json["_embedded"]["elements"].pluck("name")).to include("Dev")
    end

    it "shows a scheme with ordered type items" do
      get api_v3_paths.type_scheme(scheme.id)
      expect(last_response).to have_http_status(:ok)
      expect(json["typeItems"].map { _1.dig("_links", "type", "href") })
        .to eq([api_v3_paths.type(story.id), api_v3_paths.type(epic.id)])
      expect(json["typeItems"].first["default"]).to be true
    end

    it "returns 404 for an unknown scheme" do
      get api_v3_paths.type_scheme(0)
      expect(last_response).to have_http_status(:not_found)
    end

    it "forbids writing" do
      post api_v3_paths.type_schemes, body_for("X", [bug]), headers
      expect(last_response).to have_http_status(:forbidden)
    end

    it "hides schemes not used by a project the user may view" do
      other_project = create(:project, types: [bug])
      hidden = create(:type_scheme, name: "Hidden", types: [bug])
      TypeSchemes::SchemeService.assign(other_project, hidden)

      get api_v3_paths.type_schemes
      names = json["_embedded"]["elements"].pluck("name")
      expect(names).to include("Dev")
      expect(names).not_to include("Hidden")

      get api_v3_paths.type_scheme(hidden.id)
      expect(last_response).to have_http_status(:not_found)
    end

    it "does not list schemes for a user without view_work_packages" do
      login_as(create(:user, member_with_permissions: { project => %i[assign_type_scheme] }))

      get api_v3_paths.type_schemes
      expect(json["_embedded"]["elements"]).to be_empty

      get api_v3_paths.type_scheme(scheme.id)
      expect(last_response).to have_http_status(:not_found)
    end

    it "requires login" do
      login_as(User.anonymous)
      get api_v3_paths.type_schemes
      expect(last_response).to have_http_status(:unauthorized)

      get api_v3_paths.type_scheme(scheme.id)
      expect(last_response).to have_http_status(:unauthorized)
    end

    describe "default scheme for projects without an assignment" do
      let!(:default) { create(:type_scheme, name: "Fallback", types: [bug], is_default: true) }
      let(:unassigned) { create(:project, types: [bug]) }
      let(:unassigned_viewer) { create(:user, member_with_permissions: { unassigned => %i[view_work_packages] }) }

      before { login_as(unassigned_viewer) }

      it "lists the default scheme when auto-assign is on" do
        get api_v3_paths.type_schemes
        expect(json["_embedded"]["elements"].pluck("name")).to include("Fallback")
      end

      it "hides the default scheme (404) when auto-assign is off" do
        allow(Setting).to receive(:type_scheme_auto_assign_default?).and_return(false)

        get api_v3_paths.type_schemes
        expect(json["_embedded"]["elements"].pluck("name")).not_to include("Fallback")

        get api_v3_paths.type_scheme(default.id)
        expect(last_response).to have_http_status(:not_found)
      end
    end

    it "lets an admin see every scheme" do
      unused = create(:type_scheme, name: "Unused", types: [bug])
      login_as(admin)

      get api_v3_paths.type_schemes
      expect(json["_embedded"]["elements"].pluck("name")).to include("Dev", "Unused")
      get api_v3_paths.type_scheme(unused.id)
      expect(last_response).to have_http_status(:ok)
    end

    it "forbids PATCH for a non-admin" do
      patch api_v3_paths.type_scheme(scheme.id), { name: "Nope" }.to_json, headers
      expect(last_response).to have_http_status(:forbidden)
      expect(scheme.reload.name).to eq "Dev"
    end
  end

  describe "writing as admin" do
    before { login_as(admin) }

    it "creates and updates a scheme" do
      post api_v3_paths.type_schemes, body_for("New", [bug, epic]), headers
      expect(last_response).to have_http_status(:created)
      id = json["id"]
      expect(TypeScheme.find(id).default_type).to eq bug

      patch api_v3_paths.type_scheme(id), body_for("Renamed", [epic]), headers
      expect(last_response).to have_http_status(:ok)
      expect(TypeScheme.find(id)).to have_attributes(name: "Renamed", types: [epic])
    end

    it "creates a new type and adds it to the scheme" do
      post api_v3_paths.type_schemes, { name: "WithNew", newTypeNames: ["Sub-Tasks"] }.to_json, headers

      expect(last_response).to have_http_status(:created)
      scheme = TypeScheme.find(json["id"])
      expect(scheme.types.map(&:name)).to eq(["Sub-Tasks"])
      expect(scheme.default_type.name).to eq("Sub-Tasks")
    end

    it "stores and returns per-type colors" do
      color = create(:color)
      body = { name: "Colored",
               typeItems: [{ _links: { type: { href: api_v3_paths.type(bug.id) } },
                             position: 1, default: true, colorId: color.id }] }

      post api_v3_paths.type_schemes, body.to_json, headers

      expect(last_response).to have_http_status(:created)
      expect(json["typeItems"].first["color"]).to include("id" => color.id, "hexcode" => color.hexcode)
      expect(TypeScheme.find(json["id"]).items.first.color).to eq(color)
    end

    it "resolves a custom color hexcode on an item" do
      body = { name: "Hex",
               typeItems: [{ _links: { type: { href: api_v3_paths.type(bug.id) } },
                             position: 1, default: true, colorHex: "#a1b2c3" }] }

      post api_v3_paths.type_schemes, body.to_json, headers

      expect(last_response).to have_http_status(:created)
      expect(json["typeItems"].first["color"]).to include("hexcode" => "#A1B2C3")
      expect(TypeScheme.find(json["id"]).items.first.color.hexcode).to eq("#A1B2C3")
    end

    it "appends new types on update without dropping existing items" do
      target = create(:type_scheme, name: "Append", types: [story])

      patch api_v3_paths.type_scheme(target.id), { newTypeNames: ["Sub-Tasks"] }.to_json, headers

      expect(last_response).to have_http_status(:ok)
      expect(target.reload.types.map(&:name)).to eq([story.name, "Sub-Tasks"])
      expect(target.default_type).to eq(story)
    end

    it "reuses an existing type instead of creating a duplicate" do
      existing = create(:type, name: "Sub-Tasks")

      post api_v3_paths.type_schemes, { name: "Reuse", newTypeNames: ["sub-tasks"] }.to_json, headers

      expect(last_response).to have_http_status(:created)
      expect(TypeScheme.find(json["id"]).types).to eq([existing])
      expect(Type.where("LOWER(name) = ?", "sub-tasks").count).to eq(1)
    end

    it "rejects a non-list newTypeNames payload" do
      post api_v3_paths.type_schemes, { name: "Bad", newTypeNames: "Sub-Tasks" }.to_json, headers
      expect(last_response).to have_http_status(:bad_request)
    end

    it "does not offer deletion" do
      delete api_v3_paths.type_scheme(scheme.id)
      expect(last_response.status).to be_in([404, 405])
      expect(TypeScheme.exists?(scheme.id)).to be true
    end

    it "makes a scheme the default and toggles active" do
      patch api_v3_paths.type_scheme(scheme.id), { isDefault: true }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(scheme.reload).to be_is_default

      patch api_v3_paths.type_scheme(scheme.id), { active: false }.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
    end

    it "deactivates and reactivates a non-default scheme" do
      patch api_v3_paths.type_scheme(scheme.id), { active: false }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(scheme.reload).not_to be_active

      patch api_v3_paths.type_scheme(scheme.id), { active: true }.to_json, headers
      expect(last_response).to have_http_status(:ok)
      expect(scheme.reload).to be_active
    end

    it "rolls back item changes when the activation toggle fails" do
      default = TypeSchemes::DefaultScheme.ensure!
      before_ids = default.items.pluck(:type_id)
      body = { name: "Renamed", active: false, typeItems: [{ typeId: bug.id, position: 1, default: true }] }
      patch api_v3_paths.type_scheme(default.id), body.to_json, headers

      expect(last_response).to have_http_status(:unprocessable_entity)
      expect(default.reload.name).not_to eq "Renamed"
      expect(default.items.pluck(:type_id)).to match_array(before_ids)
    end

    it "rejects a scheme without a default type" do
      body = { name: "Bad", typeItems: [{ _links: { type: { href: api_v3_paths.type(bug.id) } }, position: 1 }] }
      post api_v3_paths.type_schemes, body.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "project assignment" do
    it "requires assign_type_scheme" do
      login_as(viewer)
      put api_v3_paths.project_type_scheme(project.id), { scheme_id: scheme.id }.to_json, headers
      expect(last_response).to have_http_status(:forbidden)
    end

    it "assigns a scheme and refuses an empty scheme_id" do
      login_as(member)
      put api_v3_paths.project_type_scheme(project.id), { scheme_id: scheme.id }.to_json, headers
      expect(last_response).to have_http_status(:no_content)
      expect(ProjectTypeScheme.find_by(project_id: project.id).scheme).to eq scheme

      put api_v3_paths.project_type_scheme(project.id), { scheme_id: nil }.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
      expect(ProjectTypeScheme.find_by(project_id: project.id).scheme).to eq scheme
    end

    it "rejects an inactive scheme" do
      login_as(member)
      inactive = create(:type_scheme, name: "Off", types: [bug])
      inactive.update_columns(active: false)
      put api_v3_paths.project_type_scheme(project.id), { scheme_id: inactive.id }.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "available types" do
    it "keeps scheme position order, not default first" do
      ordered = create(:type_scheme, name: "Pos", types: [epic, story])
      ordered.items.each { |i| i.update_columns(is_default: i.type_id == story.id) }
      TypeSchemes::SchemeService.assign(project, ordered)
      login_as(viewer)

      get api_v3_paths.project_available_types(project.id)
      expect(json["_embedded"]["elements"].pluck("id")).to eq([epic.id, story.id])
    end

    before { login_as(viewer) }

    it "returns scheme types in order, default first" do
      TypeSchemes::SchemeService.assign(project, scheme)
      get api_v3_paths.project_available_types(project.id)

      expect(last_response).to have_http_status(:ok)
      expect(json["_embedded"]["elements"].pluck("id")).to eq([story.id, epic.id])
    end

    it "is forbidden without view_work_packages" do
      login_as(create(:user, member_with_permissions: { project => %i[assign_type_scheme] }))
      get api_v3_paths.project_available_types(project.id)
      expect(last_response).to have_http_status(:forbidden)
    end

    it "warns via header when no scheme type is enabled in the project" do
      other = create(:type_scheme, name: "Disjoint", types: [create(:type)])
      TypeSchemes::SchemeService.assign(project, other)

      get api_v3_paths.project_available_types(project.id)
      expect(last_response.headers["X-Type-Scheme-Warning"]).to eq "no_enabled_types"
      expect(json["_embedded"]["elements"].pluck("id")).to match_array([epic.id, story.id, bug.id])
    end

    it "sends no warning header when the scheme intersects" do
      TypeSchemes::SchemeService.assign(project, scheme)
      get api_v3_paths.project_available_types(project.id)
      expect(last_response.headers).not_to have_key("X-Type-Scheme-Warning")
    end

    it "returns all enabled types without a scheme" do
      get api_v3_paths.project_available_types(project.id)
      expect(json["_embedded"]["elements"].pluck("id")).to match_array([epic.id, story.id, bug.id])
    end
  end

  describe "unexpected input types" do
    before { login_as(admin) }

    it "rejects non-scalar position and oversized ids without a server error" do
      body = { name: "Weird",
               typeItems: [{ typeId: bug.id, position: { a: 1 }, default: true },
                           { typeId: 99_999_999_999_999_999_999, position: 1 }] }.to_json
      post api_v3_paths.type_schemes, body, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
    end

    it "does not persist a rename when the activation toggle fails" do
      default = TypeSchemes::DefaultScheme.ensure!
      patch api_v3_paths.type_scheme(default.id), { name: "Renamed", active: false }.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
      expect(default.reload.name).not_to eq("Renamed")
    end

    it "answers 422 for a non-scalar scheme_id on assignment" do
      login_as(member)
      put api_v3_paths.project_type_scheme(project.id), { scheme_id: { a: 1 } }.to_json, headers
      expect(last_response).to have_http_status(:unprocessable_entity)
    end
  end
end
