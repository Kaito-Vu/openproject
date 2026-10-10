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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.

require "spec_helper"

RSpec.describe WorkItemQuery do
  let(:user) { create(:user) }

  it "is valid with defaults" do
    expect(described_class.new(name: "q", user:)).to be_valid
  end

  it "rejects unknown mode and bad tree" do
    expect(described_class.new(name: "q", user:, mode: "grid")).not_to be_valid
    expect(described_class.new(name: "q", user:, tree: { "op" => "xor", "children" => [] })).not_to be_valid
  end

  it "reports translated validation errors" do
    query = described_class.new(name: "q", user:, mode: "grid", tree: { "op" => "xor", "children" => [] },
                                columns: nil, sort_criteria: nil)
    query.validate
    expect(query.errors.added?(:tree, :unknown_op, op: "\"xor\"")).to be true
    expect(query.errors.added?(:columns, :invalid_shape, max: described_class::MAX_COLUMNS)).to be true
    expect(query.errors.full_messages).to include(
      "Mode must be one of flat, tree",
      "Conditions unknown op \"xor\"",
      "Columns must be an array of at most #{described_class::MAX_COLUMNS} non-blank strings",
      "Sort criteria must be an array of at most #{described_class::MAX_SORT_CRITERIA} [field, asc|desc] pairs"
    )
  end

  describe ".visible" do
    let(:project) { create(:project, member_with_permissions: { user => %i[view_work_packages] }) }
    let(:no_wp_project) { create(:project, member_with_permissions: { user => %i[view_project] }) }
    let(:hidden_project) { create(:project) }
    let(:owner) { create(:user) }

    it "follows Queries::Scopes::Visible (view_work_packages in the project, own or public)" do
      visible = [
        create(:work_item_query, user:, project:),
        create(:work_item_query, user:),
        create(:work_item_query, :public, user: owner),
        create(:work_item_query, :public, user: owner, project:)
      ]
      create(:work_item_query, user:, project: hidden_project) # own, but access to the project is gone
      create(:work_item_query, :public, user: owner, project: no_wp_project) # project visible, work packages not
      create(:work_item_query, :public, user: owner, project: hidden_project)
      create(:work_item_query, user: owner)

      expect(described_class.visible(user)).to match_array(visible)
    end

    it "shows nothing global to a user without view_work_packages anywhere" do
      create(:work_item_query, :public, user: owner)
      expect(described_class.visible(create(:user))).to be_empty
    end
  end

  it "rejects public: nil and oversized trees" do
    expect(described_class.new(name: "q", user:, public: nil)).not_to be_valid

    leaf = { "field" => "subject", "operator" => "~", "values" => ["x" * 900] }
    big = described_class.new(name: "q", user:, tree: { "op" => "and", "children" => Array.new(80) { leaf } })
    expect(big).not_to be_valid
    expect(big.errors.details[:tree]).to eq [{ error: :too_large, max: described_class::MAX_TREE_BYTES / 1.kilobyte }]
  end

  it "stores the tree with string keys" do
    query = described_class.new(tree: { op: "and", children: [{ field: "status", operator: "o", values: [] }] })
    expect(query.tree).to eq("op" => "and", "children" => [{ "field" => "status", "operator" => "o", "values" => [] }])
  end

  describe "deleting referenced records" do
    let(:other) { create(:user) }
    let(:project) { create(:project) }

    it "deletes private queries, hands public ones and updated_by to DeletedUser via Principals::DeleteJob" do
      deleted_user = create(:deleted_user)
      own = create(:work_item_query, user:)
      shared = create(:work_item_query, :public, user:)
      shared.favorites.create!(user: other)
      edited = create(:work_item_query, user: other, updated_by: user)
      WorkItemQueryFavorite.create!(user:, work_item_query: edited)

      Principals::DeleteJob.perform_now(user)

      expect(User.exists?(user.id)).to be false
      expect(described_class.exists?(own.id)).to be false
      expect(shared.reload.user_id).to eq deleted_user.id
      expect(shared.favorites.pluck(:user_id)).to eq [other.id]
      expect(edited.reload.updated_by_id).to eq deleted_user.id
      expect(WorkItemQueryFavorite.where(user_id: user.id)).to be_empty
    end

    it "removes project scoped queries (and their favourites) when the project is deleted" do
      scoped = create(:work_item_query, user:, project:)
      scoped.favorites.create!(user: other)
      global = create(:work_item_query, user:)

      result = Projects::DeleteService.new(user: create(:admin), model: project).call

      expect(result).to be_success
      expect(Project.exists?(project.id)).to be false
      expect(described_class.exists?(scoped.id)).to be false
      expect(WorkItemQueryFavorite.where(work_item_query_id: scoped.id)).to be_empty
      expect(described_class.exists?(global.id)).to be true
    end
  end

  it "tracks favorites per user" do
    query = described_class.create!(name: "q", user:)
    WorkItemQueryFavorite.create!(user:, work_item_query: query)
    expect(query.favorite_of?(user)).to be true
    expect(query.favorite_of?(create(:user))).to be false
  end

  it "validates columns" do
    [nil, "id", [1], [""], Array.new(51) { "id" }].each do |bad|
      expect(described_class.new(name: "q", user:, columns: bad)).not_to be_valid
    end
    expect(described_class.new(name: "q", user:, columns: %w[id subject])).to be_valid
  end

  it "validates sort_criteria" do
    [nil, "x", ["id"], [%w[id up]], [%w[id asc extra]], Array.new(11) { %w[id asc] }].each do |bad|
      expect(described_class.new(name: "q", user:, sort_criteria: bad)).not_to be_valid
    end
    expect(described_class.new(name: "q", user:, sort_criteria: [%w[id desc]])).to be_valid
  end
end
