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

import {
  exactMatch, highlightParts, initialActive, moveActive,
} from './work-item-combobox';

describe('work item combobox helpers', () => {
  it('moves the active option and wraps around', () => {
    expect(moveActive(0, 1, 3)).toBe(1);
    expect(moveActive(2, 1, 3)).toBe(0);
    expect(moveActive(0, -1, 3)).toBe(2);
    expect(moveActive(0, 1, 0)).toBe(-1);
  });

  it('starts on the selected option when it is shown, else on the first', () => {
    expect(initialActive(['a', 'b', 'c'], 'b')).toBe(1);
    expect(initialActive(['a', 'b', 'c'], 'zzz')).toBe(0);
    expect(initialActive([], 'a')).toBe(0);
  });

  it('splits a label around the typed text for highlighting', () => {
    expect(highlightParts('Assignee', 'sig')).toEqual({ before: 'As', match: 'sig', after: 'nee' });
    expect(highlightParts('Assignee', 'ASS')).toEqual({ before: '', match: 'Ass', after: 'ignee' });
    expect(highlightParts('Assignee', '')).toEqual({ before: 'Assignee', match: '', after: '' });
    expect(highlightParts('Assignee', 'zz')).toEqual({ before: 'Assignee', match: '', after: '' });
  });

  it('finds an exact (case-insensitive) label match for Tab, and nothing for partial text', () => {
    const opts = [{ id: 'a', name: 'Assignee' }, { id: 's', name: 'Status' }];
    expect(exactMatch(opts, ' status ')?.id).toBe('s');
    expect(exactMatch(opts, 'stat')).toBeNull();
    expect(exactMatch(opts, '')).toBeNull();
  });
});
