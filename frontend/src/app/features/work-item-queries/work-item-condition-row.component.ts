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

import { Component, EventEmitter, Input, Output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Condition } from './work-item-query-tree';

// Minimal stub; Task 6 replaces the internals but keeps this input/output contract.
@Component({
  selector: 'op-work-item-condition-row',
  standalone: true,
  imports: [FormsModule],
  template: `
    <input type="text" placeholder="field" [ngModel]="condition.field" (ngModelChange)="changed.emit({ field: $event })" />
    <input type="text" placeholder="operator" [ngModel]="condition.operator" (ngModelChange)="changed.emit({ operator: $event })" />
    <input
      type="text"
      placeholder="values (comma separated)"
      [ngModel]="condition.values.join(',')"
      (ngModelChange)="changed.emit({ values: splitValues($event) })"
    />
    <button type="button" (click)="removed.emit()">Remove</button>
  `,
})
export class WorkItemConditionRowComponent {
  @Input() condition!:Condition;

  @Output() changed = new EventEmitter<Partial<Condition>>();

  @Output() removed = new EventEmitter<void>();

  splitValues(v:string):string[] { return v.split(',').map((s) => s.trim()).filter(Boolean); }
}
