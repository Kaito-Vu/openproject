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

import { groupAndFilter } from './work-item-query-list';

const item = (over:any) => ({
  id: 1, name: 'Bugs', mode: 'flat', public: false, project_id: null, columns: [], sort_criteria: [],
  tree: { op: 'and', children: [] }, user_id: 1, favorite: false, updated_at: '2026-01-01T00:00:00Z',
  updated_by_name: 'A', ...over,
});

describe('groupAndFilter', () => {
  const items = [
    item({ id: 1, name: 'Bugs', user_id: 1 }),
    item({ id: 2, name: 'Assigned to me', user_id: 1, favorite: true }),
    item({ id: 3, name: 'Release bugs', user_id: 2, public: true, favorite: true }),
    item({ id: 4, name: 'Other private', user_id: 2, public: false }),
  ];

  it('splits own queries from shared public ones and hides private queries of others', () => {
    const out = groupAndFilter(items, { tab: 'all', keyword: '', currentUserId: 1 });
    expect(out.my.map((i) => i.id)).toEqual([2, 1]);
    expect(out.shared.map((i) => i.id)).toEqual([3]);
  });

  it('shows only favorites on the favorites tab', () => {
    const out = groupAndFilter(items, { tab: 'favorites', keyword: '', currentUserId: 1 });
    expect(out.my.map((i) => i.id)).toEqual([2]);
    expect(out.shared.map((i) => i.id)).toEqual([3]);
  });

  it('filters by keyword, case-insensitively', () => {
    const out = groupAndFilter(items, { tab: 'all', keyword: 'BUGS', currentUserId: 1 });
    expect(out.my.map((i) => i.id)).toEqual([1]);
    expect(out.shared.map((i) => i.id)).toEqual([3]);
  });
});
