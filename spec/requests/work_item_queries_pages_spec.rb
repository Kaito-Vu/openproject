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
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "Work item queries pages", type: :rails_request do
  shared_let(:project) { create(:project) }
  shared_let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:outsider) { create(:user) }

  context "when logged in with view_work_packages" do
    before { login_as user }

    it "renders the editor globally and in a project" do
      ["/queries/editor", "/projects/#{project.identifier}/queries/editor"].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("opce-work-item-query-editor")
      end
    end

    it "renders the list globally and in a project" do
      ["/queries", "/projects/#{project.identifier}/queries"].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("opce-work-item-query-list")
      end
    end
  end

  context "when logged in without permission in the project" do
    before { login_as outsider }

    it "denies the project-scoped editor" do
      get "/projects/#{project.identifier}/queries/editor"
      expect(response).to have_http_status(:forbidden).or have_http_status(:not_found)
    end
  end

  context "when anonymous" do
    it "redirects the editor to the login page" do
      get "/queries/editor"
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/login")
    end
  end
end
