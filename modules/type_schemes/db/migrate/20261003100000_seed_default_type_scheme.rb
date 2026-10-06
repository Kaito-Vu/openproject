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

# frozen_string_literal: true

class SeedDefaultTypeScheme < ActiveRecord::Migration[8.1]
  def up
    TypeSchemes::DefaultMigration.call(mode: "auto")
  end

  # Removes only what #up seeded: the untouched-name default scheme (items cascade) and its project assignments.
  # Types, projects and work packages are never touched.
  def down
    return unless table_exists?(:type_schemes)

    ids = select_values("SELECT id FROM type_schemes WHERE is_default AND name = 'Default Scheme'")
    return if ids.empty?

    list = ids.map(&:to_i).join(",")
    execute("DELETE FROM project_type_schemes WHERE scheme_id IN (#{list})")
    execute("DELETE FROM type_schemes WHERE id IN (#{list})")
  end
end
