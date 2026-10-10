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

# Brings databases that ran the first version of 20261009100000 in line with its current
# definition: no cascade on work_item_queries.user_id (Principals::DeleteJob reassigns public
# queries to DeletedUser) and no separate user_id index on favorites (the unique
# (user_id, work_item_query_id) index covers it). Fresh databases already match, so every
# step is guarded and the migration is a no-op there.
class AlignWorkItemQueryForeignKeys < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :work_item_queries, column: :user_id, if_exists: true
    add_foreign_key :work_item_queries, :users, column: :user_id

    remove_index :work_item_query_favorites, name: "index_work_item_query_favorites_on_user_id", if_exists: true
  end

  def down
    # Nothing to undo: the schema after `up` is the one 20261009100000 creates.
  end
end
