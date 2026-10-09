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

import { applySaved, buildSavePayload, WorkItemQueryItem } from './work-item-query.service';
import { emptyTree } from './work-item-query-tree';

describe('buildSavePayload', () => {
  const tree = { op: 'and' as const, children: [{ field: 'status', operator: '=', values: ['1'] }] };
  const state = { name: 'q', mode: 'tree' as const, project_id: 3, tree };

  it('uses defaults for a new query', () => {
    const p = buildSavePayload(state, null);
    expect(p.public).toBe(false);
    expect(p.columns).toEqual(['id', 'type', 'subject', 'status', 'assignee']);
    expect(p.sort_criteria).toEqual([['id', 'asc']]);
  });

  it('preserves public/columns/sort_criteria of an existing query and uses the current tree and mode', () => {
    const loaded:WorkItemQueryItem = {
      id: 1, name: 'old', mode: 'flat', public: true, project_id: null,
      columns: ['id', 'subject'], sort_criteria: [['subject', 'desc']], tree: emptyTree(),
    };
    const p = buildSavePayload(state, loaded);
    expect(p.public).toBe(true);
    expect(p.columns).toEqual(['id', 'subject']);
    expect(p.sort_criteria).toEqual([['subject', 'desc']]);
    expect(p.tree).toBe(tree);
    expect(p.mode).toBe('tree');
    expect(p.project_id).toBe(3);
  });
});

describe('applySaved', () => {
  const saved = { id: 7, name: 's' } as WorkItemQueryItem;

  it('applies the response when the editor has not loaded anything else', () => {
    const out = applySaved({ currentId: null, lastLoaded: null, loadToken: 2 }, 2, saved);
    expect(out.currentId).toBe(7);
    expect(out.lastLoaded).toBe(saved);
  });

  it('ignores the response when another query was loaded meanwhile', () => {
    const state = { currentId: 3, lastLoaded: null, loadToken: 3 };
    expect(applySaved(state, 2, saved)).toBe(state);
  });
});
