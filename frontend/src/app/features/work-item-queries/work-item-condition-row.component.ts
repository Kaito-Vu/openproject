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
import { catchError, Observable, of, startWith, switchMap } from 'rxjs';
import { Condition } from './work-item-query-tree';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import {
  AllowedValues, FieldSchema, valuesAfterOperatorChange, withSavedValues,
} from './work-item-filter-schema';
import { WorkItemFilterSchemaService } from './work-item-filter-schema.service';
import { WorkItemMultiSelectComponent } from './work-item-multi-select.component';
import { WorkItemComboboxComponent } from './work-item-combobox.component';

// One condition: field and operator come from the query form's filter schemas, the value input
// follows the value type of the chosen operator. Signals because the app runs zoneless.
@Component({
  selector: 'op-work-item-condition-row',
  standalone: true,
  imports: [FormsModule, WorkItemMultiSelectComponent, WorkItemComboboxComponent],
  styleUrls: ['./work-item-queries.shared.css', './work-item-condition-row.component.css'],
  template: `
    <div class="cell">
      <op-work-item-combobox [options]="fieldOptions()" [value]="condition().field" [label]="text.field"
        [placeholder]="text.fieldPlaceholder" (changed)="setField($event)" />
      @if (loadError()) { <div class="error" role="status">{{ text.loadError }}</div> }
    </div>

    <div class="cell">
      @if (condition().field) {
        <select class="wiq-control" [attr.aria-label]="text.operator" [ngModel]="condition().operator" (ngModelChange)="setOperator($event)">
          @if (!operator()) { <option [value]="condition().operator">{{ condition().operator }}</option> }
          @for (o of field()?.operators ?? []; track o.id) { <option [value]="o.id">{{ o.name }}</option> }
        </select>
      }
    </div>

    <div class="cell values">
      @switch (valueInput()) {
        @case ('list') {
          <op-work-item-multi-select [options]="listOptions()" [selected]="condition().values"
            [label]="text.valuesFor(fieldName())" (changed)="emitValues($event)" />
        }
        @case ('ids') {
          <input class="wiq-control" type="text" [attr.aria-label]="text.idsFor(fieldName())" [placeholder]="text.idsPlaceholder"
                 [ngModel]="condition().values.join(',')" (ngModelChange)="emitValues(splitValues($event))" />
        }
        @case ('boolean') {
          <select class="wiq-control" [attr.aria-label]="text.valueFor(fieldName())" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)">
            <option value="" disabled>{{ text.select }}</option>
            <option value="t">{{ text.yes }}</option>
            <option value="f">{{ text.no }}</option>
          </select>
        }
        @case ('date') {
          <input class="wiq-control" type="date" [attr.aria-label]="text.valueFor(fieldName())"
                 [ngModel]="(condition().values[0] ?? '').slice(0, 10)" (ngModelChange)="emitSingle($event)" />
        }
        @case ('dates') {
          <input class="wiq-control" type="date" [attr.aria-label]="text.fromFor(fieldName())" [ngModel]="pairValue(0)" (ngModelChange)="emitPair(0, $event)" />
          <span class="sep" aria-hidden="true">{{ text.to }}</span>
          <input class="wiq-control" type="date" [attr.aria-label]="text.toFor(fieldName())" [ngModel]="pairValue(1)" (ngModelChange)="emitPair(1, $event)" />
        }
        @case ('number') {
          <input class="wiq-control" type="number" [attr.step]="operator()?.type?.includes('Integer') ? 1 : 'any'" [attr.aria-label]="text.valueFor(fieldName())"
                 [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)" />
        }
        @case ('text') {
          <input class="wiq-control" type="text" [attr.aria-label]="text.valueFor(fieldName())" [placeholder]="text.value" [ngModel]="condition().values[0] ?? ''" (ngModelChange)="emitSingle($event)" />
        }
      }
    </div>
  `,
})
export class WorkItemConditionRowComponent {
  readonly condition = input.required<Condition>();

  readonly changed = output<Partial<Condition>>();

  private schema = inject(WorkItemFilterSchemaService);

  private I18n = inject(I18nService);

  private meLabel = this.I18n.t('js.label_me');

  readonly text = {
    field: this.I18n.t('js.work_item_queries.filter.field'),
    fieldPlaceholder: this.I18n.t('js.work_item_queries.filter.field_placeholder'),
    loadError: this.I18n.t('js.work_item_queries.filter.load_error'),
    operator: this.I18n.t('js.work_item_queries.filter.operator'),
    idsPlaceholder: this.I18n.t('js.work_item_queries.filter.ids_placeholder'),
    select: this.I18n.t('js.work_item_queries.filter.select_placeholder'),
    yes: this.I18n.t('js.general_text_Yes'),
    no: this.I18n.t('js.general_text_No'),
    to: this.I18n.t('js.work_item_queries.filter.to'),
    value: this.I18n.t('js.work_item_queries.filter.value'),
    valuesFor: (field:string) => this.I18n.t('js.work_item_queries.filter.values_for', { field }),
    idsFor: (field:string) => this.I18n.t('js.work_item_queries.filter.ids_for', { field }),
    valueFor: (field:string) => this.I18n.t('js.work_item_queries.filter.value_for', { field }),
    fromFor: (field:string) => this.I18n.t('js.work_item_queries.filter.from_for', { field }),
    toFor: (field:string) => this.I18n.t('js.work_item_queries.filter.to_for', { field }),
  };

  readonly loadError = signal(false);

  // Project the query runs in (null across projects): decides which filters the form offers.
  readonly projectId = input<number|null>(null);

  readonly fields = toSignal(
    toObservable(this.projectId).pipe(switchMap((id) => this.schema.fields(id).pipe(
      catchError(() => { this.loadError.set(true); return of<FieldSchema[]>([]); }),
    ))),
    { initialValue: null },
  );

  readonly fieldOptions = computed(() => (this.fields() ?? []).map((f) => ({ id: f.id, name: f.name })));

  readonly field = computed(() => this.fields()?.find((f) => f.id === this.condition().field));

  readonly fieldName = computed(() => this.field()?.name ?? this.condition().field);

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
      return this.schema.allowedValues(src).pipe(startWith(null), catchError(() => of(null)));
    })),
    { initialValue: null },
  );

  readonly listOptions = computed(() => withSavedValues(
    this.list()?.options ?? [], this.operator()?.type ?? null, this.condition().values, this.meLabel,
  ));

  // Half-entered date range: not emitted (the backend needs both) but kept on screen.
  private pairDraft = signal<string[]>([]);

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
    this.pairDraft.set([]);
    const op = this.fields()?.find((f) => f.id === id)?.operators[0];
    this.changed.emit({ field: id, operator: op?.id ?? '', values: [] });
  }

  setOperator(id:string):void {
    this.pairDraft.set([]);
    const to = this.field()?.operators.find((o) => o.id === id);
    this.changed.emit({ operator: id, values: valuesAfterOperatorChange(this.operator(), to, this.condition().values) });
  }

  emitValues(values:string[]):void { this.changed.emit({ values }); }

  emitSingle(v:string|number|null):void { this.emitValues(v == null || v === '' ? [] : [String(v)]); }

  pairValue(i:0|1):string {
    const saved = this.condition().values;
    return ((saved.length === 2 ? saved[i] : this.pairDraft()[i]) ?? '').slice(0, 10);
  }

  emitPair(i:0|1, v:string|null):void {
    const pair = [this.pairValue(0), this.pairValue(1)];
    pair[i] = v ?? '';
    this.pairDraft.set(pair);
    this.emitValues(pair.every(Boolean) ? pair : []);
  }

  splitValues(v:string):string[] { return v.split(',').map((s) => s.trim()).filter(Boolean); }
}
