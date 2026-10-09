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

RSpec.describe WorkItemQueries::Compiler do
  let(:user) { create(:admin) }
  let(:project) { create(:project, types: [t1, t2]) }
  let(:s1) { create(:status) }
  let(:s2) { create(:status) }
  let(:s3) { create(:status) }
  let(:t1) { create(:type) }
  let(:t2) { create(:type) }
  let!(:wp_t1_s1) { create(:work_package, project:, type: t1, status: s1) }
  let!(:wp_t1_s2) { create(:work_package, project:, type: t1, status: s2) }
  let!(:wp_t1_s3) { create(:work_package, project:, type: t1, status: s3) }
  let!(:wp_t2_s1) { create(:work_package, project:, type: t2, status: s1) }

  def cond(field, *ids) = { "field" => field, "operator" => "=", "values" => ids.map { it.id.to_s } }
  def group(op, *children) = { "op" => op, "children" => children }

  def run(tree)
    wiq = WorkItemQuery.new(name: "q", user:, project:, tree:)
    User.execute_as(user) { WorkItemQueries::BuildQuery.new(wiq, user:).call.results.work_packages.to_a }
  end

  it "ANDs top-level conditions" do
    expect(run(group("and", cond("type", t1), cond("status", s1)))).to contain_exactly(wp_t1_s1)
  end

  it "supports nested OR inside AND" do
    tree = group("and", cond("type", t1), group("or", cond("status", s1), cond("status", s2)))
    expect(run(tree)).to contain_exactly(wp_t1_s1, wp_t1_s2)
  end

  it "allows the same field twice in different branches" do
    tree = group("or", group("and", cond("type", t1), cond("status", s1)),
                 group("and", cond("type", t2), cond("status", s1)))
    expect(run(tree)).to contain_exactly(wp_t1_s1, wp_t2_s1)
  end

  it "returns everything for an empty tree (no implicit open-status filter)" do
    expect(run(group("and"))).to contain_exactly(wp_t1_s1, wp_t1_s2, wp_t1_s3, wp_t2_s1)
  end

  it "raises InvalidTree for an unknown field" do
    expect { run(group("and", { "field" => "nope", "operator" => "=", "values" => ["1"] })) }
      .to raise_error(described_class::InvalidTree)
  end

  describe ".or_unsafe?" do
    it "flags filters with string joins or a from clause" do
      expect(described_class.or_unsafe?(double(from: nil, joins: "INNER JOIN x ON x.id = 1"))).to be true
      expect(described_class.or_unsafe?(double(from: "(select 1) AS work_packages", joins: nil))).to be true
    end

    it "allows symbol joins and no joins" do
      expect(described_class.or_unsafe?(double(from: nil, joins: :status))).to be false
      expect(described_class.or_unsafe?(double(from: nil, joins: nil))).to be false
    end
  end
end
