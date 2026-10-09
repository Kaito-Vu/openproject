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

RSpec.describe Projects::Metrics do
  let(:today) { Date.new(2026, 10, 9) }
  let(:project) { create(:project) }
  let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  let(:open_status) { create(:status) }
  let(:closed_status) { create(:closed_status) }

  subject(:metrics) { described_class.new([project.id], user:, today:) }

  before do
    allow(Setting).to receive(:work_package_done_ratio).and_return("field")
  end

  def work_package(**attributes)
    create(:work_package, { project:, status: open_status }.merge(attributes))
  end

  describe "#progress" do
    it "weights leaf done_ratio by estimated hours and ignores parents" do
      parent = work_package
      work_package(parent:, done_ratio: 100, estimated_hours: 1)
      work_package(parent:, done_ratio: 0, estimated_hours: 3)
      work_package(done_ratio: 100, estimated_hours: nil) # unestimated counts as 1h

      # (100*1 + 0*3 + 100*1) / (1 + 3 + 1)
      expect(metrics.progress).to eq(project.id => 40)
    end
  end

  describe "#[]" do
    it "counts open, overdue, unassigned and closed work packages" do
      work_package(due_date: today - 1, assigned_to: user)
      work_package(due_date: today + 1)
      work_package(status: closed_status, assigned_to: user)

      row = metrics[project.id]
      expect(row).to have_attributes(open: 2, overdue: 1, unassigned: 1, closed: 1)
    end

    it "only counts what the user may see" do
      create(:work_package, project: create(:project))

      expect(metrics[project.id].health).to eq(:no_data)
    end

    context "for health" do
      it "is healthy when nothing is overdue and progress keeps up" do
        10.times { work_package(due_date: today + 5, start_date: today - 5, done_ratio: 60) }

        expect(metrics[project.id].health).to eq(:healthy)
      end

      it "needs attention when 10% of open work is overdue" do
        work_package(due_date: today - 1)
        9.times { work_package(due_date: today + 5, done_ratio: 100) }

        expect(metrics[project.id].health).to eq(:attention)
      end

      it "is at risk when a quarter of open work is overdue" do
        2.times { work_package(due_date: today - 1) }
        6.times { work_package(due_date: today + 5) }

        expect(metrics[project.id].health).to eq(:risk)
      end

      it "is at risk when progress lags far behind the elapsed schedule" do
        work_package(start_date: today - 90, due_date: today + 10, done_ratio: 10)

        expect(metrics[project.id].health).to eq(:risk)
      end
    end
  end

  describe "#team" do
    let(:colleague) { create(:user) }

    it "lists workload and completion per member, busiest first" do
      work_package(assigned_to: user, done_ratio: 100)
      work_package(assigned_to: colleague, due_date: today - 1, done_ratio: 0)
      work_package(assigned_to: colleague, done_ratio: 50)
      work_package(assigned_to: colleague, status: closed_status, updated_at: today)
      work_package(assigned_to: colleague, status: closed_status, updated_at: today - 60)

      rows = metrics.team(project.id, [user, colleague])

      expect(rows.map(&:user)).to eq([colleague, user])
      expect(rows.first).to have_attributes(open: 2, overdue: 1, closed_recent: 1)
      expect(rows.last).to have_attributes(open: 1, overdue: 0, progress: 100)
    end
  end
end
