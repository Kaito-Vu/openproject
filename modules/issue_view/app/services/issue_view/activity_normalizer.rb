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

module IssueView
  class ActivityNormalizer
    include ::API::V3::Activities::ActivityPropertyFormatters

    TYPES = %w[COMMENT FIELD_CHANGED ATTACHMENT_ADDED ATTACHMENT_REMOVED OTHER].freeze
    OTHER_KEYS = /\A(file_links|custom_comment|project_phase|agenda_items|participants)/

    def initialize(work_package)
      @work_package = work_package
      @activity_page = "work_packages/#{work_package.id}"
    end

    def events(journal)
      events = []
      events << comment_event(journal) if journal.notes.present?

      index = 0
      journal.details.each do |detail|
        raw = journal.render_detail(detail, html: false)
        next if raw.blank?

        html = journal.render_detail(detail, html: true, activity_page: @activity_page)
        events << detail_event(journal, index, detail, { raw:, html: })
        index += 1
      end
      events
    end

    private

    def base(journal, id, type)
      { _type: "IssueViewEvent",
        id: "#{journal.id}:#{id}",
        journalId: journal.id,
        type:,
        actor: actor(journal),
        timestamp: journal.created_at.utc.iso8601 }
    end

    def actor(journal)
      user = journal.user
      { id: user&.id, name: user&.name,
        _links: { self: { href: user && ::API::V3::Utilities::PathHelper::ApiV3Path.user(user.id) } } }
    end

    def comment_event(journal)
      base(journal, "comment", "COMMENT").merge(
        comment: { id: journal.id,
                   body: JSON.parse(formatted_notes(journal).to_json),
                   internal: journal.internal,
                   createdAt: journal.created_at.utc.iso8601,
                   updatedAt: journal.updated_at.utc.iso8601 }
      )
    end

    def detail_event(journal, index, detail, description)
      key, (old_value, new_value) = detail
      key = key.to_s

      if (match = key.match(/\Aattachments_?(\d+)\z/))
        attachment_event(base(journal, index, nil), match[1].to_i, old_value, new_value, description)
      elsif key == "cause" || key.match?(OTHER_KEYS)
        base(journal, index, "OTHER").merge(description:, causeType: cause_type(key, new_value))
      else
        base(journal, index, "FIELD_CHANGED").merge(field: key, raw: { from: old_value, to: new_value }, description:)
      end
    end

    def attachment_event(event, id, old_value, new_value, description)
      type = if old_value.nil? then "ATTACHMENT_ADDED"
             elsif new_value.nil? then "ATTACHMENT_REMOVED"
             else "OTHER"
             end
      event.merge(type:, attachment: { id:, fileName: new_value || old_value }, description:)
    end

    def cause_type(key, new_value)
      new_value["type"] if key == "cause" && new_value.respond_to?(:[]) && !new_value.is_a?(String)
    end
  end
end
