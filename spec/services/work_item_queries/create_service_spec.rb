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

RSpec.describe WorkItemQueries::CreateService, "integration" do
  shared_let(:project) { create(:project) }
  shared_let(:other_project) { create(:project) }

  let(:permissions) { %i[view_work_packages save_queries] }
  let(:user) { create(:user, member_with_permissions: { project => permissions }) }

  def create_query(**attributes)
    described_class.new(user:).call(name: "q", **attributes)
  end

  it "creates the query owned and last updated by the user" do
    result = create_query(project_id: project.id, tree: { op: "and", children: [] })

    expect(result).to be_success
    expect(result.result).to be_persisted
    expect(result.result).to have_attributes(user:, updated_by: user, project:, public: false,
                                             columns: %w[id type subject status assignee], sort_criteria: [%w[id asc]])
  end

  it "ignores a client-sent owner" do
    result = create_query(user_id: create(:user).id)
    expect(result).to be_success
    expect(result.result.user).to eq user
  end

  context "without save_queries" do
    let(:permissions) { %i[view_work_packages] }

    it "is unauthorized in the project and globally" do
      [project.id, nil].each do |project_id|
        result = create_query(project_id:)
        expect(result).to be_failure
        expect(result.errors.symbols_for(:base)).to eq [:error_unauthorized]
      end
    end
  end

  it "rejects a project the user cannot see" do
    result = create_query(project_id: other_project.id)
    expect(result.errors.symbols_for(:project)).to eq [:error_not_found]
  end

  context "with save_queries but without view_work_packages in the project" do
    # The member can see the project, but the visible scope would hide the saved query from its owner.
    let(:permissions) { %i[view_project save_queries] }

    it "rejects the project like an invisible one" do
      result = create_query(project_id: project.id)
      expect(result).to be_failure
      expect(result.errors.symbols_for(:project)).to eq [:error_not_found]
      expect(WorkItemQuery.count).to eq 0
    end
  end

  it "rejects public without manage_public_queries, as an error on public" do
    [project.id, nil].each do |project_id|
      result = create_query(project_id:, public: true)
      expect(result).to be_failure
      expect(result.errors.symbols_for(:public)).to eq [:not_allowed]
      expect(result.errors.symbols_for(:base)).to be_empty
    end
  end

  context "with manage_public_queries" do
    let(:permissions) { %i[view_work_packages save_queries manage_public_queries] }

    it "creates public queries in the project and globally" do
      expect(create_query(project_id: project.id, public: true)).to be_success
      expect(create_query(public: true)).to be_success
    end
  end

  it "rejects anonymous users" do
    result = described_class.new(user: User.anonymous).call(name: "q")
    expect(result.errors.symbols_for(:base)).to include(:error_unauthorized)
  end
end
