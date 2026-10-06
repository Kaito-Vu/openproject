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
require Rails.root.join("modules/type_schemes/db/migrate/20261002100000_create_type_schemes").to_s

RSpec.describe CreateTypeSchemes do
  it "drops only its own tables on rollback and keeps types and work packages" do
    story = create(:type)
    project = create(:project, types: [story])
    create(:work_package, project:, type: story)
    counts = [Type.count, WorkPackage.count, Project.count]

    migration = described_class.new
    migration.migrate(:down)
    begin
      %w[type_schemes type_scheme_items project_type_schemes].each do |table|
        expect(ActiveRecord::Base.connection.table_exists?(table)).to be false
      end
      expect([Type.count, WorkPackage.count, Project.count]).to eq counts
    ensure
      migration.migrate(:up)
      [TypeScheme, TypeSchemeItem, ProjectTypeScheme].each(&:reset_column_information)
    end
  end
end

require Rails.root.join("modules/type_schemes/db/migrate/20261003100000_seed_default_type_scheme").to_s

RSpec.describe SeedDefaultTypeScheme do
  it "removes the seeded default scheme and its assignments on rollback, keeping types, projects and work packages" do
    story = create(:type)
    project = create(:project, types: [story])
    create(:work_package, project:, type: story)
    default = create(:type_scheme, name: TypeSchemes::DefaultScheme::NAME, types: [story], is_default: true)
    custom = create(:type_scheme, name: "Custom", types: [story])
    other_project = create(:project, types: [story])
    ProjectTypeScheme.create!(project:, scheme: default)
    ProjectTypeScheme.create!(project: other_project, scheme: custom)
    counts = [Type.count, WorkPackage.count, Project.count]

    described_class.new.migrate(:down)

    expect(TypeScheme.exists?(default.id)).to be false
    expect(TypeSchemeItem.where(scheme_id: default.id)).to be_empty
    expect(ProjectTypeScheme.where(scheme_id: default.id)).to be_empty
    expect(TypeScheme.exists?(custom.id)).to be true
    expect(ProjectTypeScheme.where(project: other_project, scheme: custom)).to exist
    expect([Type.count, WorkPackage.count, Project.count]).to eq counts
  end

  it "does nothing when no default scheme named like the seed exists" do
    renamed = create(:type_scheme, name: "Renamed by admin", is_default: true)

    expect { described_class.new.migrate(:down) }.not_to change(TypeScheme, :count)
    expect(TypeScheme.exists?(renamed.id)).to be true
  end
end
