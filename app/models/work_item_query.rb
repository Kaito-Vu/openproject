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
  EMPTY_TREE = { "op" => "and", "children" => [] }.freeze

  belongs_to :user
  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :project, optional: true
  has_many :favorites, class_name: "WorkItemQueryFavorite", dependent: :delete_all

  validates :name, presence: true, length: { maximum: 255 }
  validates :mode, inclusion: { in: MODES }
  validate :tree_shape

  scope :visible, ->(user) { where(user_id: user.id).or(where(public: true)) }

  def favorite_of?(user)
    favorites.exists?(user_id: user.id)
  end

  private

  def tree_shape
    WorkItemQueries::TreeValidator.errors(tree).each { |message| errors.add(:tree, message) }
  end
end
