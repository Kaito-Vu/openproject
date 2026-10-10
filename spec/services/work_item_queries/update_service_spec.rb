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

RSpec.describe WorkItemQueries::UpdateService, "integration" do
  shared_let(:project) { create(:project) }
  shared_let(:other_project) { create(:project) }

  let(:permissions) { %i[view_work_packages save_queries] }
  let(:other_permissions) { %i[view_work_packages save_queries] }
  let(:user) do
    create(:user, member_with_permissions: { project => permissions, other_project => other_permissions })
  end
  let(:query) { create(:work_item_query, user:, project:) }

  def update(model = query, **attributes)
    described_class.new(user:, model:).call(**attributes)
  end

  it "updates the owner's query and records the editor" do
    query.update_columns(updated_by_id: nil)
    result = update(name: "renamed")

    expect(result).to be_success
    expect(query.reload).to have_attributes(name: "renamed", updated_by: user)
  end

  it "is unauthorized for someone else's (public) query" do
    other = create(:work_item_query, :public, user: create(:user), project:)
    expect(update(other, name: "hacked").errors.symbols_for(:base)).to eq [:error_unauthorized]
  end

  context "without save_queries" do
    let(:permissions) { %i[view_work_packages] }

    it "is unauthorized" do
      expect(update(name: "x").errors.symbols_for(:base)).to eq [:error_unauthorized]
    end
  end

  it "rejects publishing without manage_public_queries" do
    result = update(public: true)
    expect(result.errors.symbols_for(:public)).to eq [:not_allowed]
    expect(query.reload.public).to be false
  end

  context "with manage_public_queries in the query's project only" do
    let(:permissions) { %i[view_work_packages save_queries manage_public_queries] }

    it "lets the owner edit the public query" do
      query.update!(public: true)
      expect(update(name: "renamed")).to be_success
    end

    it "rejects moving a public query into a project without the permission" do
      query.update!(public: true)
      result = update(project_id: other_project.id)
      expect(result.errors.symbols_for(:public)).to eq [:not_allowed]
      expect(query.reload.project).to eq project
    end
  end

  it "lets the owner of an already public query edit it without the permission" do
    query.update!(public: true)
    expect(update(name: "renamed")).to be_success
  end

  it "rejects a project the user cannot see and a null public flag" do
    result = update(project_id: create(:project).id, public: nil)
    expect(result.errors.symbols_for(:project)).to eq [:error_not_found]
    expect(result.errors.symbols_for(:public)).to eq [:inclusion]
  end
end
