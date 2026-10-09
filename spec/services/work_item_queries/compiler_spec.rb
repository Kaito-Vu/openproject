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

  describe "OR-unsafe leaves" do
    let(:query) { Query.new(name: "q", user:, project:) }

    before { allow(described_class).to receive(:or_unsafe?).and_return(true) }

    it "raises InvalidTree inside an OR group" do
      tree = group("or", cond("status", s1), cond("status", s2))

      expect { described_class.new(query).call(tree) }.to raise_error(described_class::InvalidTree, /OR group/)
    end

    it "is accepted at the top-level AND" do
      tree = group("and", cond("status", s1), cond("status", s2))

      expect { described_class.new(query).call(tree) }.not_to raise_error
    end
  end

  describe ".or_unsafe?" do
    it "flags filters with string joins" do
      expect(described_class.or_unsafe?(double(joins: "INNER JOIN x ON x.id = 1"))).to be true
    end

    it "allows symbol joins and no joins" do
      expect(described_class.or_unsafe?(double(joins: :status))).to be false
      expect(described_class.or_unsafe?(double(joins: nil))).to be false
    end
  end

  describe "filters whose condition is not in #where" do
    let(:other_user) { create(:user) }
    let(:role) { create(:work_package_role, permissions: %i[view_work_packages]) }

    before { create(:member, user: other_user, project:, entity: wp_t1_s1, roles: [role]) }

    it "rejects sharedWithUser at the top-level AND and inside nested groups" do
      leaf = { "field" => "sharedWithUser", "operator" => "=", "values" => [other_user.id.to_s] }

      expect { run(group("and", leaf)) }.to raise_error(described_class::InvalidTree, /not supported/)
      expect { run(group("and", cond("type", t1), group("or", cond("status", s1), leaf))) }
        .to raise_error(described_class::InvalidTree, /not supported/)
    end

    it "rejects relatable" do
      leaf = { "field" => "relatable", "operator" => "relates", "values" => [wp_t1_s2.id.to_s] }

      expect { run(group("and", leaf)) }.to raise_error(described_class::InvalidTree, /not supported/)
    end

    it "flags real filter classes by their apply_to, from and left_outer_joins" do
      build = ->(name) { "Queries::WorkPackages::Filter::#{name}".constantize.then { it.create!(name: it.key) } }
      flagged = %w[SharedWithUserFilter RelatableFilter].map(&build)
      plain = %w[StatusFilter SubjectFilter].map(&build)

      expect(flagged.map { described_class.unsupported?(it) }).to all(be true)
      expect(plain.map { described_class.unsupported?(it) }).to all(be false)

      status, subject = plain
      allow(status).to receive(:left_outer_joins).and_return(:x)
      allow(subject).to receive(:from).and_return("x")
      expect(plain.map { described_class.unsupported?(it) }).to all(be true)
    end
  end

  describe "ordinary filters" do
    it "filters by subject" do
      wp_t1_s2.update_columns(subject: "find the needle here")

      expect(run(group("and", { "field" => "subject", "operator" => "~", "values" => ["needle"] })))
        .to contain_exactly(wp_t1_s2)
    end

    it "filters by dueDate between two dates" do
      dated = create(:work_package, project:, type: t2, status: s1, start_date: nil, due_date: Date.new(2026, 1, 15))
      create(:work_package, project:, type: t2, status: s1, start_date: nil, due_date: Date.new(2026, 2, 15))

      leaf = { "field" => "dueDate", "operator" => "<>d", "values" => %w[2026-01-01 2026-01-31] }
      expect(run(group("and", leaf))).to contain_exactly(dated)
    end

    it "filters by assignee me, also inside OR" do
      wp_t1_s3.update_columns(assigned_to_id: user.id)
      me = { "field" => "assignee", "operator" => "=", "values" => ["me"] }

      expect(run(group("and", me))).to contain_exactly(wp_t1_s3)
      expect(run(group("or", me, cond("type", t2)))).to contain_exactly(wp_t1_s3, wp_t2_s1)
    end

    it "filters by a custom field" do
      cf = create(:string_wp_custom_field, is_for_all: true, is_filter: true, types: [t1, t2])
      CustomValue.create!(customized: wp_t1_s1, custom_field: cf, value: "alpha")
      CustomValue.create!(customized: wp_t2_s1, custom_field: cf, value: "beta")

      leaf = { "field" => "customField#{cf.id}", "operator" => "~", "values" => ["alp"] }
      expect(run(group("or", leaf, cond("status", s3)))).to contain_exactly(wp_t1_s1, wp_t1_s3)
    end
  end
end
