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

require "spec_helper"

RSpec.describe ::Screens::LayoutService do
  let(:screen) { create(:screen, screen_type: "create") }

  it "replaces the whole layout and normalises positions" do
    result = described_class.replace(screen, [
      { name: "General", items: [{ field_key: "subject" }, { field_key: "priority" }] },
      { name: "Details", items: [{ field_key: "description" }] }
    ])

    expect(result).to be_success
    screen.reload
    expect(screen.sections.pluck(:name)).to eq(%w[General Details])
    expect(screen.sections.first.items.pluck(:field_key)).to eq(%w[subject priority])
    expect(screen.sections.first.position).to eq(1)
    expect(screen.sections.second.position).to eq(2)
    expect(screen.sections.first.items.first.position).to eq(1)
  end

  it "rejects an unknown field" do
    result = described_class.replace(screen, [{ name: "General", items: [{ field_key: "does_not_exist" }] }])
    expect(result).to be_failure
    expect(result.errors.details[:base]).to include(error: :unknown_field)
  end

  it "rejects duplicate fields" do
    result = described_class.replace(screen, [
      { name: "General", items: [{ field_key: "subject" }, { field_key: "subject" }] }
    ])
    expect(result).to be_failure
    expect(result.errors.details[:base]).to include(error: :duplicate_field)
  end

  it "rejects too many items" do
    items = ::Screens::Fields.native_keys.first(3).map { |key| { field_key: key } }
    stub_const("Screen::MAX_ITEMS", 1)
    result = described_class.replace(screen, [{ name: "General", items: }])
    expect(result).to be_failure
    expect(result.errors.details[:base]).to include(error: :too_many_items)
  end

  describe ".edit" do
    let(:section) { create(:screen_section, screen:, position: 1) }

    it "bumps updated_at so the ETag of PUT layout changes" do
      before = screen.reload.updated_at
      travel_to(1.minute.from_now) { described_class.edit(screen) { |locked| locked.sections.create!(name: "New", position: 1) } }
      expect(screen.reload.updated_at).to be > before
    end

    it "rolls back and reports required_not_placed when an in-use create screen loses subject" do
      create(:screen_item, screen:, section:, field_key: "subject", position: 1)
      create(:screen_scheme_item, create_screen: screen)
      result = described_class.edit(screen) { |locked| locked.items.each(&:destroy) }
      expect(result).to be_failure
      expect(result.errors.details[:base]).to include(error: :required_not_placed)
      expect(screen.reload.items.count).to eq(1)
    end
  end

  describe ".edit conflicts" do
    it "returns a structured failure on RecordNotUnique" do
      result = described_class.edit(screen) { raise ActiveRecord::RecordNotUnique }
      expect(result).to be_failure
      expect(result.errors.details[:base]).to include(error: :conflict)
    end
  end

  describe ".place" do
    let(:section) { create(:screen_section, screen:, position: 1) }
    let!(:items) do
      %w[subject priority description].each_with_index.map do |key, index|
        create(:screen_item, screen:, section:, field_key: key, position: index + 1)
      end
    end

    it "renumbers siblings so positions stay unique and contiguous" do
      described_class.place(items.last, section.items.to_a, 1)
      expect(section.items.reload.sort_by(&:position).map(&:field_key)).to eq(%w[description subject priority])
      expect(section.items.pluck(:position).sort).to eq([1, 2, 3])
    end

    it "keeps the current position when none is given, even for a stored position of 0" do
      items.last.update_column(:position, 0)
      described_class.place(items.last, section.items.reload.to_a, nil)
      expect(section.items.reload.sort_by(&:position).map(&:field_key)).to eq(%w[description subject priority])
      described_class.place(items.second, section.items.reload.to_a, nil)
      expect(items.second.reload.position).to eq(3)
    end

    it "clamps below 1 to the first position and above the range to the last" do
      described_class.place(items.last, section.items.to_a, 0)
      expect(items.last.reload.position).to eq(1)
      described_class.place(items.first, section.items.reload.to_a, 99)
      expect(section.items.pluck(:position).sort).to eq([1, 2, 3])
    end
  end

  describe ".compact" do
    it "closes the gap after a delete" do
      section = create(:screen_section, screen:, position: 1)
      a = create(:screen_item, screen:, section:, field_key: "subject", position: 1)
      create(:screen_item, screen:, section:, field_key: "priority", position: 5)
      a.destroy
      described_class.compact(section.items.reload.to_a)
      expect(section.items.pluck(:position)).to eq([1])
    end
  end
end
