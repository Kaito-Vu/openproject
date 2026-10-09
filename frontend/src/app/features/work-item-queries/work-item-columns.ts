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

// One work package as embedded in the execute/results response (WorkPackageRepresenter).
export interface ResultElement {
  id:number;
  subject:string;
  _links:Record<string, { href?:string|null; title?:string }|undefined>;
  [property:string]:unknown;
}

const prop = (name:string) => `js.work_packages.properties.${name}`;

// API column ids; WorkItemQueries::BuildQuery converts them to Query column names. Labels are i18n keys.
export const COLUMN_CATALOG:readonly { id:string; labelKey:string }[] = [
  { id: 'id', labelKey: 'js.work_item_queries.columns.id' },
  { id: 'type', labelKey: prop('type') },
  { id: 'subject', labelKey: prop('subject') },
  { id: 'status', labelKey: prop('status') },
  { id: 'assignee', labelKey: prop('assignee') },
  { id: 'priority', labelKey: prop('priority') },
  { id: 'project', labelKey: prop('projectName') },
  { id: 'author', labelKey: prop('author') },
  { id: 'startDate', labelKey: prop('startDate') },
  { id: 'dueDate', labelKey: prop('dueDate') },
  { id: 'percentageDone', labelKey: prop('percentComplete') },
  { id: 'createdAt', labelKey: prop('createdAt') },
  { id: 'updatedAt', labelKey: prop('updatedAt') },
];

export const DEFAULT_COLUMNS = ['id', 'type', 'subject', 'status', 'assignee'];

const LINK_COLUMNS = new Set(['type', 'status', 'assignee', 'priority', 'project', 'author']);

// i18n key of a column's label; null for columns outside the catalog (shown by id).
export function columnLabelKey(id:string):string|null { return COLUMN_CATALOG.find((c) => c.id === id)?.labelKey ?? null; }

// Display text of one cell; timestamps are shown as "YYYY-MM-DD HH:MM" (UTC, as sent by the API).
export function cellValue(el:ResultElement, column:string):string {
  if (LINK_COLUMNS.has(column)) { return el._links[column]?.title ?? ''; }
  const value = el[column] as string|number|null|undefined; // the catalog's plain columns are scalars
  if (value == null) { return ''; }
  if (column === 'percentageDone') { return `${String(value)}%`; }
  if (column === 'createdAt' || column === 'updatedAt') { return String(value).replace('T', ' ').slice(0, 16); }
  return String(value);
}

// Turning a column on or off keeps the selection in catalog order.
export function toggleColumn(selected:string[], id:string, on:boolean):string[] {
  return COLUMN_CATALOG.map((c) => c.id).filter((c) => (c === id ? on : selected.includes(c)));
}
