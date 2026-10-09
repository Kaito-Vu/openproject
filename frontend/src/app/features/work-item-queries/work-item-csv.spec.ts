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
  const row = (over = {}) => ({ id: 1, type: 'Task', subject: 's', status: 'New', assignee: 'Ann', ...over });

  it('writes a header and CRLF line ends', () => {
    expect(toCsv([row()])).toBe('﻿id,type,subject,status,assignee\r\n1,Task,s,New,Ann\r\n');
  });

  it('quotes commas, quotes and newlines', () => {
    const csv = toCsv([row({ subject: 'a,"b"\nc' })]);
    expect(csv).toContain('"a,""b""\nc"');
  });

  it('neutralises spreadsheet formulas', () => {
    [' =1+1', '=1+1', '+1', '-1', '@x', '\tx', '\rx'].forEach((v) => {
      const cell = toCsv([row({ subject: v })]).split('\r\n')[1].split(',')[2];
      expect(cell.replace(/^"/, '').startsWith("'")).toBe(true);
    });
  });

  it('starts with a UTF-8 BOM', () => {
    expect(toCsv([]).startsWith('﻿')).toBe(true);
  });

  it('keeps numeric ids untouched', () => {
    expect(toCsv([row({ id: 42 })]).split('\r\n')[1].startsWith('42,')).toBe(true);
  });
});
