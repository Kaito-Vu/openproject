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

import { CellFormat, cellValue, RAW_FORMAT } from './work-item-columns';
import { ResultRow } from './work-item-results.component';

function cell(value:string):string {
  let s = String(value);
  // Formula injection: spreadsheets evaluate cells whose first non-blank character is one of these.
  if (/^[\t\r]/.test(s) || /^[=+\-@]/.test(s.trimStart())) { s = `'${s}`; }
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

// Same columns, header labels and cell text as the results table; BOM so Excel opens it as UTF-8.
export function toCsv(
  rows:Pick<ResultRow, 'element'>[],
  columns:string[],
  opts:{ label?:(column:string) => string; format?:CellFormat } = {},
):string {
  const label = opts.label ?? ((c:string) => c);
  const lines = [columns.map(label), ...rows.map((r) => columns.map((c) => cellValue(r.element, c, opts.format ?? RAW_FORMAT)))]
    .map((line) => `${line.map(cell).join(',')}\r\n`);
  return `\uFEFF${lines.join('')}`;
}

// Replaces characters invalid in file names (and control chars) with underscores.
export function safeFileName(name:string, fallback:string):string {
  const clean = [...name].map((c) => (c.charCodeAt(0) < 32 || '/\\:*?"<>|'.includes(c) ? '_' : c)).join('').trim();
  return clean || fallback;
}

// Saves `csv` as a download through a temporary link in the given document.
export function downloadCsv(doc:Document, fileName:string, csv:string):void {
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const a = doc.createElement('a');
  a.href = url;
  a.download = fileName;
  doc.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => { URL.revokeObjectURL(url); }, 1000);
}
