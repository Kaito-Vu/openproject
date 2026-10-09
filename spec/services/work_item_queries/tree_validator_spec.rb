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

RSpec.describe WorkItemQueries::TreeValidator do
  def leaf(field = "status") = { "field" => field, "operator" => "=", "values" => ["1"] }

  def nest(depth)
    node = leaf
    (depth - 1).times { node = { "op" => "and", "children" => [node] } }
    node
  end

  it "accepts an empty root group" do
    expect(described_class.errors({ "op" => "and", "children" => [] })).to be_empty
  end

  it "accepts nested groups" do
    tree = { "op" => "and", "children" => [leaf, { "op" => "or", "children" => [leaf, leaf("type")] }] }
    expect(described_class.errors(tree)).to be_empty
  end

  it "rejects a non-group root" do
    expect(described_class.errors(leaf)).not_to be_empty
  end

  it "rejects an unknown op" do
    expect(described_class.errors({ "op" => "xor", "children" => [] })).not_to be_empty
  end

  it "rejects a condition without field or with non-array values" do
    bad = { "op" => "and", "children" => [{ "field" => "", "operator" => "=", "values" => [] }] }
    expect(described_class.errors(bad)).not_to be_empty
    bad = { "op" => "and", "children" => [{ "field" => "status", "operator" => "=", "values" => "1" }] }
    expect(described_class.errors(bad)).not_to be_empty
  end

  it "rejects trees deeper than MAX_DEPTH" do
    # nest(n) wraps a leaf in n-1 groups; with the root that makes n groups deep.
    deep = { "op" => "and", "children" => [nest(WorkItemQuery::MAX_DEPTH + 1)] } # 6 groups
    expect(described_class.errors(deep)).not_to be_empty
    ok = { "op" => "and", "children" => [nest(WorkItemQuery::MAX_DEPTH)] } # 5 groups
    expect(described_class.errors(ok)).to be_empty
  end

  it "rejects more than MAX_CONDITIONS conditions" do
    tree = { "op" => "and", "children" => Array.new(WorkItemQuery::MAX_CONDITIONS + 1) { leaf } }
    expect(described_class.errors(tree)).not_to be_empty
  end
end
