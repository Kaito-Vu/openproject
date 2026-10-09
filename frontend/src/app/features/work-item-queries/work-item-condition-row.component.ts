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

import { Component, computed, inject, input, output, signal } from '@angular/core';
import { toObservable, toSignal } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { catchError, Observable, of, switchMap } from 'rxjs';
import { Condition } from './work-item-query-tree';
import { AllowedValues, FieldSchema, valuesAfterOperatorChange } from './work-item-filter-schema';
import { WorkItemFilterSchemaService } from './work-item-filter-schema.service';

// One condition: field and operator come from the query form's filter schemas, the value input
// follows the value type of the chosen operator. Signals because the app runs zoneless.
@Component({
  selector: 'op-work-item-condition-row',
  standalone: true,
  imports: [FormsModule],
  template: `
    <select aria-label="Field" [ngModel]="condition().field" (ngModelChange)="setField($event)">
      @if (!condition().field) { <option value="" disabled>Field…</option> }
      @if (condition().field && !field()) { <option [value]="condition().field">{{ condition().field }}</option> }
      @for (f of fields() ?? []; track f.id) { <option [value]="f.id">{{ f.name }}</option> }
    </select>

    @if (condition().field) {
      <select aria-label="Operator" [ngModel]="condition().operator" (ngModelChange)="setOperator($event)">
        @if (!operator()) { <option [value]="condition().operator">{{ condition().operator }}</option> }
        @for (o of field()?.operators ?? []; track o.id) { <option [value]="o.id">{{ o.name }}</option> }
      </select>
    }

    @switch (valueInput()) {
      @case ('list') {
        <select multiple aria-label="Values" [ngModel]="condition().values" (ngModelChange)="emitValues($event)">
          @for (o of list()!.options; track o.id) { <option [value]="o.id">{{ o.name }}</option> }
        </select>
      }
      @case ('ids') {
        <input type="text" aria-label="Values (comma separated ids)" placeholder="ids, comma separated"
               [ngModel]="condition().values.join(',')" (ngModelChange)="emitValues(splitValues($event))" />
      }
      @case ('boolean') {
        <select aria-label="Value" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)">
          <option value="" disabled>…</option>
          <option value="t">Yes</option>
          <option value="f">No</option>
        </select>
      }
      @case ('date') {
        <input type="date" aria-label="Value" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)" />
      }
      @case ('dates') {
        <input type="date" aria-label="From" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitPair(0, $event)" />
        <input type="date" aria-label="To" [ngModel]="condition().values[1] ?? ''" (ngModelChange)="emitPair(1, $event)" />
      }
      @case ('number') {
        <input type="number" step="any" aria-label="Value" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)" />
      }
      @case ('text') {
        <input type="text" aria-label="Value" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)" />
      }
    }

    <button type="button" aria-label="Remove condition" (click)="removed.emit()">Remove</button>
    @if (loadError()) { <span class="op-wiq-row-error">Could not load filter definitions</span> }
  `,
})
export class WorkItemConditionRowComponent {
  readonly condition = input.required<Condition>();

  readonly changed = output<Partial<Condition>>();

  readonly removed = output<void>();

  private schema = inject(WorkItemFilterSchemaService);

  readonly loadError = signal(false);

  readonly fields = toSignal(
    this.schema.fields().pipe(catchError(() => { this.loadError.set(true); return of<FieldSchema[]>([]); })),
    { initialValue: null },
  );

  readonly field = computed(() => this.fields()?.find((f) => f.id === this.condition().field));

  readonly operator = computed(() => this.field()?.operators.find((o) => o.id === this.condition().operator));

  // Inline options (custom fields) or the collection href to load them from.
  private readonly listSource = computed(() => {
    const op = this.operator();
    return op?.kind === 'list' ? (op.options ?? op.allowedHref) : null;
  });

  readonly list = toSignal(
    toObservable(this.listSource).pipe(switchMap((src):Observable<AllowedValues|null> => {
      if (src == null) { return of(null); }
      if (typeof src !== 'string') { return of({ options: src, complete: true }); }
      return this.schema.allowedValues(src).pipe(catchError(() => of(null)));
    })),
    { initialValue: null },
  );

  // ponytail: list values fall back to an ids text input while options load, on load errors, and when the
  // collection is truncated by the server (e.g. work packages); a search-as-you-type picker is the upgrade.
  readonly valueInput = computed(() => {
    const op = this.operator();
    if (!this.condition().field) { return 'none'; }
    if (!op) { return this.condition().values.length ? 'ids' : 'none'; } // schema loading or unknown here: keep values editable
    if (op.kind === 'list') { return this.list()?.complete ? 'list' : 'ids'; }
    return op.kind;
  });

  setField(id:string):void {
    const op = this.fields()?.find((f) => f.id === id)?.operators[0];
    this.changed.emit({ field: id, operator: op?.id ?? '', values: [] });
  }

  setOperator(id:string):void {
    const to = this.field()?.operators.find((o) => o.id === id);
    this.changed.emit({ operator: id, values: valuesAfterOperatorChange(this.operator(), to, this.condition().values) });
  }

  emitValues(values:string[]):void { this.changed.emit({ values }); }

  emitSingle(v:string|number|null):void { this.emitValues(v == null || v === '' ? [] : [String(v)]); }

  emitPair(i:0|1, v:string|null):void {
    const pair = [this.condition().values[0] ?? '', this.condition().values[1] ?? ''];
    pair[i] = v ?? '';
    this.emitValues(pair.some(Boolean) ? pair : []);
  }

  splitValues(v:string):string[] { return v.split(',').map((s) => s.trim()).filter(Boolean); }
}
