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

import { cellValue, columnLabel, ResultElement, toggleColumn } from './work-item-columns';

describe('cellValue', () => {
  const el:ResultElement = {
    id: 42,
    subject: 'Fix login',
    startDate: '2026-01-02',
    dueDate: null,
    percentageDone: 30,
    createdAt: '2026-10-09T08:27:15.317Z',
    updatedAt: '2026-10-10T09:05:00.000Z',
    _links: {
      self: { href: '/api/v3/work_packages/42', title: 'Fix login' },
      type: { href: '/api/v3/types/1', title: 'Task' },
      status: { href: '/api/v3/statuses/1', title: 'New' },
      assignee: { href: null },
      priority: { href: '/api/v3/priorities/8', title: 'Normal' },
      project: { href: '/api/v3/projects/3', title: 'Demo' },
      author: { href: '/api/v3/users/4', title: 'Ann Admin' },
    },
  };

  it('reads link titles', () => {
    expect(['type', 'status', 'priority', 'project', 'author'].map((c) => cellValue(el, c)))
      .toEqual(['Task', 'New', 'Normal', 'Demo', 'Ann Admin']);
  });

  it('renders an unset link (no title) as empty', () => {
    expect(cellValue(el, 'assignee')).toBe('');
    expect(cellValue({ ...el, _links: {} }, 'assignee')).toBe('');
  });

  it('formats plain properties', () => {
    expect(cellValue(el, 'id')).toBe('42');
    expect(cellValue(el, 'subject')).toBe('Fix login');
    expect(cellValue(el, 'startDate')).toBe('2026-01-02');
    expect(cellValue(el, 'dueDate')).toBe('');
    expect(cellValue(el, 'percentageDone')).toBe('30%');
    expect(cellValue(el, 'createdAt')).toBe('2026-10-09 08:27');
    expect(cellValue(el, 'updatedAt')).toBe('2026-10-10 09:05');
  });
});

describe('toggleColumn', () => {
  it('adds and removes columns keeping catalog order', () => {
    expect(toggleColumn(['subject', 'id'], 'type', true)).toEqual(['id', 'type', 'subject']);
    expect(toggleColumn(['id', 'type', 'subject'], 'type', false)).toEqual(['id', 'subject']);
  });
});

describe('columnLabel', () => {
  it('falls back to the id for unknown columns', () => {
    expect(columnLabel('dueDate')).toBe('Finish date');
    expect(columnLabel('storyPoints')).toBe('storyPoints');
  });
});
