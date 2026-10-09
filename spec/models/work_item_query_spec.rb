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

  it "scopes visible to owner or public" do
    mine = described_class.create!(name: "mine", user:)
    pub = described_class.create!(name: "pub", user: create(:user), public: true)
    described_class.create!(name: "other", user: create(:user))
    expect(described_class.visible(user)).to contain_exactly(mine, pub)
  end

  it "tracks favorites per user" do
    query = described_class.create!(name: "q", user:)
    WorkItemQueryFavorite.create!(user:, work_item_query: query)
    expect(query.favorite_of?(user)).to be true
    expect(query.favorite_of?(create(:user))).to be false
  end
end
