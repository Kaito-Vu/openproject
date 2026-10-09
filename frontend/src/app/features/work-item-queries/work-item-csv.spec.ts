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

import { toCsv } from './work-item-csv';

describe('toCsv', () => {
  const links = { type: { title: 'Task' }, status: { title: 'New' }, assignee: { title: 'Ann' } };
  const row = (over = {}) => ({ element: { id: 1, subject: 's', _links: links, ...over } });
  const csv = (rows:ReturnType<typeof row>[]) => toCsv(rows, ['id', 'type', 'subject', 'status', 'assignee']);

  it('writes a header and CRLF line ends', () => {
    expect(csv([row()])).toBe('﻿id,type,subject,status,assignee\r\n1,Task,s,New,Ann\r\n');
  });

  it('quotes commas, quotes and newlines', () => {
    const out = csv([row({ subject: 'a,"b"\nc' })]);
    expect(out).toContain('"a,""b""\nc"');
  });

  it('neutralises spreadsheet formulas', () => {
    [' =1+1', '=1+1', '+1', '-1', '@x', '\tx', '\rx'].forEach((v) => {
      const cell = csv([row({ subject: v })]).split('\r\n')[1].split(',')[2];
      expect(cell.replace(/^"/, '').startsWith("'")).toBe(true);
    });
  });

  it('starts with a UTF-8 BOM', () => {
    expect(csv([]).startsWith('﻿')).toBe(true);
  });

  it('keeps numeric ids untouched', () => {
    expect(csv([row({ id: 42 })]).split('\r\n')[1].startsWith('42,')).toBe(true);
  });
});

describe('toCsv with selected columns', () => {
  it('uses the given columns in the given order', () => {
    const element = { id: 5, subject: 's', percentageDone: 40, _links: { priority: { title: 'High' } } };
    expect(toCsv([{ element }], ['priority', 'percentageDone', 'id'])).toBe('﻿priority,percentageDone,id\r\nHigh,40%,5\r\n');
  });
});
