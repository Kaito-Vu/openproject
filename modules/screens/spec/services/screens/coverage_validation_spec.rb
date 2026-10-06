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

RSpec.describe ::Screens::CoverageValidation do
  let(:type) { create(:type) }
  let(:project) { create(:project, types: [type]) }
  let(:scheme) { create(:screen_scheme) }
  let(:screen) { create(:create_screen) }
  let(:item) { create(:screen_scheme_item, scheme:, type:, create_screen: screen) }

  def place(field_key, visible: true)
    section = screen.sections.first || create(:screen_section, screen:)
    create(:screen_item, screen:, section:, field_key:, visible:)
  end

  describe ".scheme_item" do
    before { create(:project_screen_scheme, project:, scheme:) }

    it "reports required fields that the create screen does not place" do
      result = described_class.scheme_item(item)
      expect(result.errors).to include(a_hash_including(code: :required_not_placed, field: "subject",
                                                        type_id: type.id, project_id: project.id))
    end

    it "is clean once the required fields are placed visibly" do
      place("subject")
      expect(described_class.scheme_item(item.reload).errors).to be_empty
    end

    it "treats an invisible placement as not placed" do
      place("subject", visible: false)
      expect(described_class.scheme_item(item.reload).errors.pluck(:code)).to include(:required_not_placed)
    end

    it "ignores a row without create screen" do
      row = create(:screen_scheme_item, scheme: create(:screen_scheme), type: create(:type),
                                        create_screen: nil, edit_screen: create(:edit_screen))
      expect(described_class.scheme_item(row).errors).to be_empty
    end

    it "checks only the given project before an assignment exists" do
      other = create(:project, types: [type])
      result = described_class.scheme_item(item, project_ids: [other.id])
      expect(result.errors.pluck(:project_id).uniq).to eq([other.id])
    end

    it "degrades to a warning above the project cap" do
      allow(::Screens::RequiredSet).to receive(:for_scheme_type).and_return(:skipped)
      result = described_class.scheme_item(item)
      expect(result.errors).to be_empty
      expect(result.warnings).to eq([:skipped_due_to_scale])
    end

    it "reports hidden_and_required instead of required_not_placed for a required field hidden by a real F02 rule" do
      skip "field_rules module is not loaded" unless defined?(::FieldRuleSet)

      rule_set = create(:field_rule_set, rule_attributes: [{ field_key: "priority", hidden: true }])
      field_scheme = create(:field_rule_scheme, mapping: { type => rule_set })
      ProjectFieldRuleScheme.find_or_create_by!(project:, scheme: field_scheme)
      ::Screens::Resolver.reset_cache
      # Only the natively required part is stubbed; the hidden part comes from the real rule above.
      allow(::Screens::RequiredSet).to receive(:for_scheme_type).and_return({ project.id => %w[subject priority] })
      place("subject")

      result = described_class.scheme_item(item.reload)
      expect(result.errors).to eq([{ code: :hidden_and_required, field: "priority",
                                     type_id: type.id, project_id: project.id }])
    end
  end

  describe ".warnings_for" do
    it "warns about placed fields that F02 hides for a using project" do
      stub_const("FieldRules::Resolver", Class.new) unless defined?(::FieldRules::Resolver)
      hidden = Struct.new(:key, :hidden).new("priority", true)
      place("priority")
      item
      create(:project_screen_scheme, project:, scheme:)
      allow(::FieldRules::Resolver).to receive(:for_many).and_return({ [project.id, type.id] => [hidden] })

      expect(described_class.warnings_for(screen.reload))
        .to include({ code: "hidden_but_placed", fields: ["priority"] })
    end

    it "has no hidden_but_placed warning for an unused screen" do
      place("priority")
      expect(described_class.warnings_for(screen.reload).pluck(:code)).not_to include("hidden_but_placed")
    end
  end

  describe "fail-open logging" do
    it "logs an error and returns no warnings when the F02 lookup raises" do
      stub_const("FieldRules::Resolver", Class.new) unless defined?(::FieldRules::Resolver)
      place("priority")
      item
      create(:project_screen_scheme, project:, scheme:)
      allow(::FieldRules::Resolver).to receive(:for_many).and_raise("boom")
      allow(Rails.error).to receive(:report)

      expect(OpenProject.logger).to receive(:error).with(/\[screens\] hidden_but_placed check failed.*boom/)
      expect(described_class.warnings_for(screen.reload).pluck(:code)).not_to include("hidden_but_placed")
    end
  end
end
