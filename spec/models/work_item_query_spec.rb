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

  it "scopes visible to own queries and public ones that are global or in a visible project" do
    visible_project = create(:project, member_with_permissions: { user => %i[view_work_packages] })
    hidden_project = create(:project)
    mine = described_class.create!(name: "mine", user:, project: hidden_project)
    pub = described_class.create!(name: "pub", user: create(:user), public: true)
    pub_visible = described_class.create!(name: "pv", user: create(:user), public: true, project: visible_project)
    described_class.create!(name: "ph", user: create(:user), public: true, project: hidden_project)
    described_class.create!(name: "other", user: create(:user))
    expect(described_class.visible(user)).to contain_exactly(mine, pub, pub_visible)
  end

  describe "deleting referenced records" do
    let(:other) { create(:user) }
    let(:project) { create(:project) }

    it "removes the user's queries and favourites and nullifies updated_by via Principals::DeleteJob" do
      create(:deleted_user)
      own = described_class.create!(name: "own", user:)
      described_class.create!(name: "own fav", user:).favorites.create!(user: other)
      edited = described_class.create!(name: "edited", user: other, updated_by: user)
      WorkItemQueryFavorite.create!(user:, work_item_query: edited)

      Principals::DeleteJob.perform_now(user)

      expect(User.exists?(user.id)).to be false
      expect(described_class.exists?(own.id)).to be false
      expect(described_class.where(user_id: user.id)).to be_empty
      expect(edited.reload.updated_by_id).to be_nil
      expect(WorkItemQueryFavorite.where(user_id: user.id)).to be_empty
      expect(WorkItemQueryFavorite.where.not(work_item_query_id: described_class.select(:id))).to be_empty
    end

    it "removes project scoped queries (and their favourites) when the project is deleted" do
      scoped = described_class.create!(name: "scoped", user:, project:)
      scoped.favorites.create!(user: other)
      global = described_class.create!(name: "global", user:)

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
