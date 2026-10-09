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

class CreateWorkItemQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :work_item_queries do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :updated_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :project, null: true, foreign_key: { on_delete: :cascade }
      t.boolean :public, null: false, default: false
      t.string :mode, null: false, default: "flat"
      t.jsonb :columns, null: false, default: %w[id type subject status assignee]
      t.jsonb :sort_criteria, null: false, default: [%w[id asc]]
      t.jsonb :tree, null: false, default: { "op" => "and", "children" => [] }
      t.timestamps null: false
    end

    create_table :work_item_query_favorites do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :work_item_query, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps null: false
    end
    add_index :work_item_query_favorites, %i[user_id work_item_query_id], unique: true, name: "idx_wiq_favorites_unique"
  end
end
