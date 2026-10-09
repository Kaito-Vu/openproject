//-- copyright
// OpenProject is an open source project management software.
// Copyright (C) the OpenProject GmbH
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License version 3.
//
// OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
// Copyright (C) 2006-2013 Jean-Philippe Lang
// Copyright (C) 2010-2013 the ChiliProject Team
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// See COPYRIGHT and LICENSE files for more details.
//++

import { filterOptions, popoverPosition, selectedChips, toggleValue } from './work-item-multi-select';

const options = [{ id: '1', name: 'New' }, { id: '2', name: 'In progress' }, { id: '3', name: 'Closed' }];

describe('work item multi select helpers', () => {
  it('filters options by label, case-insensitively, and returns all for an empty search', () => {
    expect(filterOptions(options, 'PROG').map((o) => o.id)).toEqual(['2']);
    expect(filterOptions(options, '  ')).toBe(options);
    expect(filterOptions(options, 'zzz')).toEqual([]);
  });

  it('toggles a value without duplicating and keeps the pick order', () => {
    expect(toggleValue(['2'], '1', true)).toEqual(['2', '1']);
    expect(toggleValue(['2', '1'], '2', true)).toEqual(['1', '2']);
    expect(toggleValue(['2', '1'], '2', false)).toEqual(['1']);
  });

  it('labels chips by option name and falls back to the id for unknown values', () => {
    expect(selectedChips(options, ['3', 'me'])).toEqual([{ id: '3', name: 'Closed' }, { id: 'me', name: 'me' }]);
  });

  it('places the popover below the trigger, or above when there is no room below', () => {
    const rect = { left: 10, top: 500, bottom: 532, width: 120 };
    expect(popoverPosition(rect, 1000)).toEqual({ left: 10, top: 536, width: 260 });
    expect(popoverPosition(rect, 600)).toEqual({ left: 10, top: 196, width: 260 });
    expect(popoverPosition({ ...rect, top: 40, bottom: 72 }, 300).top).toBe(76);
  });
});
