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

module TypeSchemes
  module Resolver
    module_function

    CACHE_KEY = :type_scheme_cache

    def for_project(project)
      return if project.nil?
      return fallback_scheme if project.id.nil?

      by_project = cache[:projects]
      return by_project[project.id] if by_project.key?(project.id)

      by_project[project.id] = find_active_scheme(project.id) || fallback_scheme
    end

    # Projects without an (active) assignment use the default scheme only while auto-assign is on;
    # when it is off they are not filtered at all (native behaviour).
    def fallback_scheme
      default_scheme if Setting.type_scheme_auto_assign_default?
    end

    def type_allowed?(project, type_id)
      scheme = for_project(project)
      return true unless scheme

      enabled_ids = project.project_types.map(&:type_id)
      scheme_ids = scheme.items.map(&:type_id) & enabled_ids
      warn_disjoint(project, scheme) if scheme_ids.empty?
      scheme_ids.empty? || scheme_ids.include?(type_id)
    end

    # True when the project's scheme has types but none is enabled in the project. Resolution then
    # fails open to the native enabled types; surfaced to the project settings page and the API.
    def disjoint?(project)
      scheme = for_project(project)
      return false unless scheme&.items&.any?

      (scheme.items.map(&:type_id) & project.project_types.map(&:type_id)).empty?
    end

    def reset_cache
      RequestStore.store.delete(CACHE_KEY)
    end

    # Returns +scope+ untouched when no scheme applies, so project settings stay native.
    # With +default_first+ the scheme's default type leads, so callers taking +.first+ preselect it.
    def allowed_types(project, scope = nil, default_first: true)
      scheme = for_project(project)
      return scope || project.enabled_types unless scheme

      # Memoised per request for the common call (project's own enabled types, no custom scope).
      return compute_allowed_types(project, scheme, scope, default_first) if scope || project.id.nil?

      key = [project.id, default_first, project.project_types.map(&:type_id).sort]
      (cache[:allowed] ||= {})[key] ||= compute_allowed_types(project, scheme, project.enabled_types, default_first)
    end

    def compute_allowed_types(project, scheme, scope, default_first)
      scope ||= project.enabled_types
      by_id = scope.index_by(&:id)
      ordered = scheme.items.sort_by { |i| [default_first && i.is_default ? 0 : 1, i.position, i.id.to_i] }
                      .filter_map { |i| by_id[i.type_id] }
      warn_disjoint(project, scheme) if ordered.empty?
      ordered.presence || scope
    end

    # Logged once per project and request to keep the log readable.
    def warn_disjoint(project, scheme)
      warned = (cache[:warned] ||= Set.new)
      return unless warned.add?(project.id)

      Rails.logger.warn("[type_schemes] scheme #{scheme.id} has no type enabled in project #{project.id}; " \
                        "not filtering, using the project's enabled types")
    end

    def find_active_scheme(project_id)
      scheme_id = ProjectTypeScheme.where(project_id:).pick(:scheme_id)
      return unless scheme_id

      schemes = cache[:schemes]
      schemes[scheme_id] = TypeScheme.active.includes(:items).find_by(id: scheme_id) unless schemes.key?(scheme_id)
      schemes[scheme_id]
    end

    def default_scheme
      cache[:default] = DefaultScheme.current unless cache.key?(:default)
      cache[:default]
    end

    def cache
      RequestStore.store[CACHE_KEY] ||= { projects: {}, schemes: {} }
    end
  end
end
