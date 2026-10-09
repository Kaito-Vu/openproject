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

export type Op = 'and'|'or';

import { NgTemplateOutlet } from '@angular/common';
import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

export interface ResultRow {
  id:number; subject:string; type:string; status:string; assignee:string; parentId:number|null; children:ResultRow[];
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

@Component({
  selector: 'op-work-item-results',
  standalone: true,
  imports: [NgTemplateOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <table class="generic-table">
      <thead>
        <tr><th>ID</th><th>Type</th><th>Subject</th><th>Status</th><th>Assignee</th></tr>
      </thead>
      <tbody>
        @for (row of (mode === 'tree' ? nested() : rows); track row.id) {
          <ng-container *ngTemplateOutlet="rowTpl; context: { row: row, depth: 0 }" />
        }
      </tbody>
    </table>
    <ng-template #rowTpl let-row="row" let-depth="depth">
      <tr>
        <td>{{ row.id }}</td>
        <td>{{ row.type }}</td>
        <td [style.padding-left.px]="depth * 16">{{ row.subject }}</td>
        <td>{{ row.status }}</td>
        <td>{{ row.assignee }}</td>
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

  nested():ResultRow[] { return nestByParent(this.rows); }
}
