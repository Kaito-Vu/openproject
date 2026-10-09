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

import { cellValue } from './work-item-columns';
import { ResultRow } from './work-item-results.component';

function cell(value:string):string {
  let s = String(value);
  // Formula injection: spreadsheets evaluate cells whose first non-blank character is one of these.
  if (/^[\t\r]/.test(s) || /^[=+\-@]/.test(s.trimStart())) { s = `'${s}`; }
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

// Same columns (and cell text) as the results table; BOM so Excel opens the file as UTF-8.
export function toCsv(rows:Pick<ResultRow, 'element'>[], columns:string[]):string {
  const lines = [columns, ...rows.map((r) => columns.map((c) => cellValue(r.element, c)))]
    .map((line) => `${line.map(cell).join(',')}\r\n`);
  return `\uFEFF${lines.join('')}`;
}
