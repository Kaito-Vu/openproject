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

class WorkItemQuery < ApplicationRecord
  MODES = %w[flat tree].freeze
  MAX_DEPTH = 5
  MAX_CONDITIONS = 50
  MAX_COLUMNS = 50
  SORT_DIRECTIONS = %w[asc desc].freeze
  MAX_SORT_CRITERIA = 10
  EMPTY_TREE = { "op" => "and", "children" => [] }.freeze

  belongs_to :user
  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :project, optional: true
  has_many :favorites, class_name: "WorkItemQueryFavorite", dependent: :delete_all

  validates :name, presence: true, length: { maximum: 255 }
  validates :mode, inclusion: { in: MODES, message: "must be one of #{MODES.join(", ")}" }
  validate :tree_shape
  validate :columns_shape
  validate :sort_criteria_shape

  scope :visible, ->(user) { where(user_id: user.id).or(where(public: true)) }

  def favorite_of?(user)
    favorites.exists?(user_id: user.id)
  end

  private

  def columns_shape
    return if columns.is_a?(Array) && columns.size <= MAX_COLUMNS && columns.all? { |c| c.is_a?(String) && c.present? }

    errors.add(:columns, "must be an array of at most #{MAX_COLUMNS} non-blank strings")
  end

  def sort_criteria_shape
    ok = sort_criteria.is_a?(Array) && sort_criteria.size <= MAX_SORT_CRITERIA &&
         sort_criteria.all? { |s| s.is_a?(Array) && s.size == 2 && s.all?(String) && SORT_DIRECTIONS.include?(s[1]) }
    errors.add(:sort_criteria, "must be an array of at most #{MAX_SORT_CRITERIA} [field, asc|desc] pairs") unless ok
  end

  def tree_shape
    WorkItemQueries::TreeValidator.errors(tree).each { |message| errors.add(:tree, message) }
  end
end
