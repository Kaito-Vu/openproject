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

import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { cellValue, columnLabel, DEFAULT_COLUMNS, ResultElement } from './work-item-columns';

export interface ResultRow {
  id:number; parentId:number|null; element:ResultElement; children:ResultRow[];
}

export function nestByParent(flat:Omit<ResultRow, 'children'>[]):ResultRow[] {
  const byId = new Map<number, ResultRow>(flat.map((r) => [r.id, { ...r, children: [] }]));
  const roots:ResultRow[] = [];
  byId.forEach((row) => {
    const parent = row.parentId != null ? byId.get(row.parentId) : undefined;
    (parent ? parent.children : roots).push(row);
  });
  return roots;
}

// Cells are computed from the raw element, so toggling a column shows it without re-running.
@Component({
  selector: 'op-work-item-results',
  standalone: true,
  imports: [NgTemplateOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <table class="generic-table">
      <thead>
        <tr>@for (c of columns; track c) { <th>{{ label(c) }}</th> }</tr>
      </thead>
      <tbody>
        @for (row of (mode === 'tree' ? nested() : rows); track row.id) {
          <ng-container *ngTemplateOutlet="rowTpl; context: { row: row, depth: 0 }" />
        }
      </tbody>
    </table>
    <ng-template #rowTpl let-row="row" let-depth="depth">
      <tr>
        @for (c of columns; track c) {
          <td [style.padding-left.px]="c === 'subject' && depth ? depth * 16 : null">{{ cell(row.element, c) }}</td>
        }
      </tr>
      @if (mode === 'tree') {
        @for (child of row.children; track child.id) {
          <ng-container *ngTemplateOutlet="rowTpl; context: { row: child, depth: depth + 1 }" />
        }
      }
    </ng-template>
  `,
})
export class WorkItemResultsComponent {
  @Input() rows:ResultRow[] = [];

  @Input() mode:'flat'|'tree' = 'flat';

  @Input() columns:string[] = DEFAULT_COLUMNS;

  readonly cell = cellValue;

  readonly label = columnLabel;

  nested():ResultRow[] { return nestByParent(this.rows); }
}
