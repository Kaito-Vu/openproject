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
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "open_project/static/homescreen"
require "open_project/static/links"

OpenProject::Static::Homescreen.manage :blocks do |blocks|
  blocks.push(
    { name: "dashboard_kpis" },
    { name: "portfolio_health" },
    { name: "my_work" },
    { name: "favorite_projects" },
    { name: "status_distribution" },
    { name: "recent_activity" },
    {
      name: "administration",
      if: Proc.new { User.current.admin? }
    }
  )
end

OpenProject::Static::Homescreen.manage :links do |links|
  links.push(
    {
      label: :user_guides,
      icon: "milestone",
      url_key: :user_guides
    },
    {
      label: :glossary,
      icon: "op-glossar",
      url_key: :glossary
    },
    {
      label: :shortcuts,
      icon: "op-shortcuts",
      url_key: :shortcuts
    },
    {
      label: :forums,
      icon: "comment-discussion",
      url_key: :forums
    },
    {
      label: :impressum,
      icon: "info",
      url_key: :impressum
    }
  )
end
