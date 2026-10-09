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

RSpec.describe Homescreen::DashboardStats do
  let(:today) { Date.new(2026, 10, 9) }
  let(:project) { create(:project) }
  let(:other_project) { create(:project) }
  let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  let(:open_status) { create(:status) }
  let(:closed_status) { create(:closed_status) }

  subject(:stats) { described_class.new(user:, today:) }

  before do
    allow(Setting).to receive(:work_package_done_ratio).and_return("field")
  end

  def work_package(**attributes)
    create(:work_package, { project:, status: open_status, assigned_to: user }.merge(attributes))
  end

  describe "deadline groups" do
    let!(:overdue) { work_package(due_date: today - 1) }
    let!(:due_today) { work_package(due_date: today) }
    let!(:due_soon) { work_package(due_date: today + 7) }
    let!(:later) { work_package(due_date: today + 8) }
    let!(:no_date) { work_package }
    let!(:closed) { work_package(due_date: today - 1, status: closed_status) }
    let!(:someone_elses) { work_package(due_date: today - 1, assigned_to: create(:user)) }
    let!(:invisible) { create(:work_package, project: other_project, assigned_to: user, due_date: today - 1) }

    it "puts each open, visible, assigned work package in exactly one group" do
      expect(stats.overdue).to contain_exactly(overdue)
      expect(stats.due_today).to contain_exactly(due_today)
      expect(stats.due_soon).to contain_exactly(due_soon)
      expect(stats.assigned_open).to contain_exactly(overdue, due_today, due_soon, later, no_date)
    end
  end

  describe "#visible_projects" do
    before { other_project }

    it "returns every active project the user may see, member or not" do
      other_project.update!(public: true)
      user

      expect(stats.visible_projects).to contain_exactly(project, other_project)
    end
  end

  describe "#projects" do
    before { other_project }

    it "returns only active projects the user is a member of" do
      expect(stats.projects).to contain_exactly(project)
    end
  end

  describe "#status_distribution" do
    it "counts the user's work packages per status" do
      work_package
      work_package
      work_package(status: closed_status)

      expect(stats.status_distribution).to eq([[open_status, 2], [closed_status, 1]].sort_by { |s, _| s.position })
    end
  end
end
