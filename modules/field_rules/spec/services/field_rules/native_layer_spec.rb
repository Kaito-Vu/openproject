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

RSpec.describe "Field rules: native layer, grandfather warning, system actor and import paths" do # rubocop:disable RSpec/DescribeClass
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:bug) { create(:type, name: "Bug") }
  shared_let(:status) { create(:default_status) }
  shared_let(:priority) { create(:default_priority) }
  shared_let(:custom_field) { create(:string_wp_custom_field, is_for_all: true, types: [bug]) }
  shared_let(:project) { create(:project, types: [bug]) }
  shared_let(:user) do
    create(:user, member_with_permissions: { project => %i[view_work_packages add_work_packages edit_work_packages] })
  end

  let(:key) { "custom_field_#{custom_field.id}" }

  def assign_rules(rules)
    rule_set = create(:field_rule_set, rule_attributes: rules)
    ProjectFieldRuleScheme.create!(project:, scheme: create(:field_rule_scheme, mapping: { bug => rule_set }))
    FieldRules::Resolver.reset_cache
  end

  # Writes the native layer onto the real base variant of the type instead of stubbing a double.
  def stub_native(required_ids: [], description: nil)
    TypeVariant.default_variant.where(type_id: bug.id)
               .update_all(required_attributes: required_ids.map { |id| "custom_field_#{id}" },
                           default_work_package_description: description)
    bug.variants.reset
  end

  def schema_json(work_package, current_user)
    schema = API::V3::WorkPackages::Schema::SpecificWorkPackageSchema.new(work_package:)
    representer = API::V3::WorkPackages::Schema::WorkPackageSchemaRepresenter
                    .create(schema, self_link: nil, current_user:)
    JSON.parse(representer.to_json)
  end

  describe "FieldRules::Validator.describe (layer 0 merge)" do
    it "reports native required custom fields and the default description with their source" do
      assign_rules([{ field_key: "priority", hidden: true }])
      stub_native(required_ids: [custom_field.id], description: "Template")

      configuration = FieldRules::Validator.describe(project, bug)

      expect(configuration[key]).to have_attributes(required: true, source: :native)
      expect(configuration["description"]).to have_attributes(default_value: "Template", source: :native)
      expect(configuration["priority"]).to have_attributes(hidden: true, source: :rule_set)
    end

    it "marks fields touched by both layers and lets a rule default win over the template" do
      assign_rules([{ field_key: key, required: true }, { field_key: "description", default_value: "Rule default" }])
      stub_native(required_ids: [custom_field.id], description: "Template")

      configuration = FieldRules::Validator.describe(project, bug)

      expect(configuration[key].source).to eq :both
      expect(configuration["description"]).to have_attributes(default_value: "Rule default", source: :rule_set)
    end

    it "does not change what is enforced: Resolver keeps returning the rules only" do
      assign_rules([{ field_key: "priority", hidden: true }])
      stub_native(required_ids: [custom_field.id])

      expect(FieldRules::Resolver.for(project, bug).keys).to eq ["priority"]
    end

    it "serves the merged layer and the real source through the API" do
      stub_native(required_ids: [custom_field.id])
      login_as(user)

      get api_v3_paths.project_type_field_rules(project.id, bug.id)

      field = JSON.parse(last_response.body)["fields"].find { |entry| entry["key"] == key }
      expect(field).to include("required" => true, "source" => "native")
    end
  end

  describe "grandfather warning" do
    before { assign_rules([{ field_key: "description", required: true }]) }

    let(:legacy) { create(:work_package, project:, type: bug, author: user, status:, description: nil) }

    it "lists required fields an existing work package leaves empty, without blocking" do
      expect(FieldRules::Validator.grandfathered_fields(legacy, FieldRules::Resolver.for(project, bug)))
        .to eq ["description"]

      legacy.subject = "Unrelated change"
      errors = WorkPackages::UpdateContract.new(legacy, user).tap(&:validate).errors
      expect(errors.symbols_for(:description)).to be_empty
    end

    it "does not warn for new or filled work packages" do
      configuration = FieldRules::Resolver.for(project, bug)

      expect(FieldRules::Validator.grandfathered_fields(build(:work_package, project:, type: bug), configuration))
        .to be_empty
      filled = create(:work_package, project:, type: bug, author: user, status:, description: "Filled")
      expect(FieldRules::Validator.grandfathered_fields(filled, configuration)).to be_empty
    end

    it "exposes requiredButEmpty in the schema of the existing work package only" do
      expect(schema_json(legacy, user)["description"]).to include("required" => true, "requiredButEmpty" => true)
      expect(schema_json(build(:work_package, project:, type: bug), user)["description"])
        .not_to have_key("requiredButEmpty")
    end
  end

  describe "system actor in the schema patch" do
    it "leaves the schema untouched for the system user" do
      assign_rules([{ field_key: "description", required: true }, { field_key: "category", hidden: true }])
      work_package = build(:work_package, project:, type: bug)
      allow(User).to receive(:current).and_return(User.system)

      parsed = schema_json(work_package, User.system)

      expect(parsed["description"]["required"]).to be(false)
      expect(parsed).to have_key("category")
    end
  end

  describe "import and mail handler path (R9)" do
    before { assign_rules([{ field_key: "description", required: true }]) }

    it "creates work packages as the system user without rules" do
      result = WorkPackages::CreateService
                 .new(user: User.system, contract_class: WorkPackages::CreateContract)
                 .call(project:, type: bug, subject: "Imported", status:, priority:, author: user)

      expect(result).to be_success
    end

    it "enforces the rules for a user on create but not on unrelated updates of legacy work packages" do
      created = WorkPackages::CreateService.new(user:).call(project:, type: bug, subject: "Mail", status:, priority:)
      expect(created).to be_failure
      expect(created.errors.symbols_for(:description)).to include(:required_by_field_rules)

      legacy = create(:work_package, project:, type: bug, author: user, status:, description: nil)
      updated = WorkPackages::UpdateService.new(user:, model: legacy).call(subject: "Reply by mail")
      expect(updated).to be_success
    end
  end

  describe "Backlogs story_points" do
    before { skip "Backlogs is not loaded" unless defined?(OpenProject::Backlogs) }

    let(:backlogs_project) do
      create(:project, types: [bug], enabled_module_names: %w[work_package_tracking backlogs])
    end

    before do
      FieldRules::Fields.register("story_points", attributes: %w[story_points], schema_key: "storyPoints")
      rule_set = create(:field_rule_set, rule_attributes: [{ field_key: "story_points", read_only: true }])
      ProjectFieldRuleScheme.create!(project: backlogs_project,
                                     scheme: create(:field_rule_scheme, mapping: { bug => rule_set }))
      FieldRules::Resolver.reset_cache
    end

    after { FieldRules::Fields.reset_registry! }

    it "makes story_points read-only in the contract and the schema" do
      member = create(:user, member_with_permissions: { backlogs_project => %i[view_work_packages edit_work_packages] })
      work_package = create(:work_package, project: backlogs_project, type: bug, status:)

      expect(WorkPackages::UpdateContract.new(work_package, member).writable_attributes).not_to include("story_points")
      expect(schema_json(work_package, member).dig("storyPoints", "writable")).to be(false)
    end
  end
end
