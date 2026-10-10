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
import {
  ChangeDetectionStrategy, Component, computed, inject, input,
} from '@angular/core';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { TimezoneService } from 'core-app/core/datetime/timezone.service';
import {
  CellFormat, cellValue, columnLabelKey, DEFAULT_COLUMNS, ResultElement,
} from './work-item-columns';
import { idFromHref } from './work-item-filter-schema';
import type { ExecuteResponse } from './work-item-query.service';

export interface ResultRow {
  id:number; parentId:number|null; element:ResultElement; children:ResultRow[];
}

// Work packages of an execute/results response, with their parent id for Tree mode.
export function toResultRows(res:ExecuteResponse):ResultRow[] {
  return res._embedded.results._embedded.elements.map((element) => {
    const parentHref = element._links.parent?.href;
    return {
      id: element.id, parentId: parentHref ? Number(idFromHref(parentHref)) : null, element, children: [],
    };
  });
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

// Display formats of the user (timezone, date format): shared by the table and the CSV export.
export function timezoneFormat(timezone:TimezoneService):CellFormat {
  return {
    date: (v) => timezone.formattedDate(v),
    datetime: (v) => timezone.formattedDatetime(v),
  };
}

// Indentation stops growing after this many levels so deep chains keep room for the subject.
const MAX_INDENT_LEVELS = 8;

// Cells are computed from the raw element, so toggling a column shows it without re-running.
@Component({
  selector: 'op-work-item-results',
  standalone: true,
  imports: [NgTemplateOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrls: ['./work-item-queries.shared.css', './work-item-results.component.css'],
  template: `
    <div class="table-wrap">
      <table>
        <thead>
          <tr>@for (c of columns(); track c) { <th scope="col" [class.col-id]="c === 'id'">{{ label(c) }}</th> }</tr>
        </thead>
        <tbody>
          @for (row of shown(); track row.id) {
            <ng-container *ngTemplateOutlet="rowTpl; context: { row: row, depth: 0 }" />
          }
        </tbody>
      </table>
    </div>
    <ng-template #rowTpl let-row="row" let-depth="depth">
      <tr>
        @for (c of columns(); track c) {
          <td [class.col-id]="c === 'id'" [class.col-subject]="c === 'subject'">
            @switch (c) {
              @case ('id') { <a class="id" [href]="wpPath(row.id)">#{{ row.id }}</a> }
              @case ('subject') {
                <span class="subject" [style.padding-inline-start.px]="indent(depth)">
                  @if (depth > 0) {
                    <span class="branch" aria-hidden="true"></span>
                    <span class="sr-only">{{ levelText(depth + 1) }}</span>
                  }
                  <a [href]="wpPath(row.id)">{{ cell(row.element, c) }}</a>
                </span>
              }
              @case ('type') { @if (cell(row.element, c); as v) { <span class="chip chip-type">{{ v }}</span> } }
              @case ('status') { @if (cell(row.element, c); as v) { <span class="chip chip-status">{{ v }}</span> } }
              @case ('priority') { @if (cell(row.element, c); as v) { <span class="chip chip-priority">{{ v }}</span> } }
              @default { {{ cell(row.element, c) }} }
            }
          </td>
        }
      </tr>
      @if (mode() === 'tree') {
        @for (child of row.children; track child.id) {
          <ng-container *ngTemplateOutlet="rowTpl; context: { row: child, depth: depth + 1 }" />
        }
      }
    </ng-template>
  `,
})
export class WorkItemResultsComponent {
  readonly rows = input<ResultRow[]>([]);

  readonly mode = input<'flat'|'tree'>('flat');

  readonly columns = input<string[]>(DEFAULT_COLUMNS);

  private I18n = inject(I18nService);

  private pathHelper = inject(PathHelperService);

  private format = timezoneFormat(inject(TimezoneService));

  readonly shown = computed(() => (this.mode() === 'tree' ? nestByParent(this.rows()) : this.rows()));

  cell(el:ResultElement, column:string):string { return cellValue(el, column, this.format); }

  // UI page of the work package (not its API href), under the app base path.
  wpPath(id:number):string { return this.pathHelper.workPackagePath(id); }

  indent(depth:number):number { return Math.min(depth, MAX_INDENT_LEVELS) * 22; }

  levelText(level:number):string { return this.I18n.t('js.work_item_queries.editor.level', { level }); }

  label(id:string):string {
    const key = columnLabelKey(id);
    return key ? this.I18n.t(key) : id;
  }
}
