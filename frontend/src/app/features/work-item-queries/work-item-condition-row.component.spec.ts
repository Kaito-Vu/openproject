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

import { TestBed } from '@angular/core/testing';
import {
  NEVER, Observable, of, throwError,
} from 'rxjs';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { WorkItemConditionRowComponent } from './work-item-condition-row.component';
import { WorkItemFilterSchemaService } from './work-item-filter-schema.service';
import { AllowedValues, FieldSchema, OperatorSchema } from './work-item-filter-schema';
import { Condition } from './work-item-query-tree';

const op = (id:string, kind:OperatorSchema['kind'], extra:Partial<OperatorSchema> = {}):OperatorSchema => ({
  id, name: id, kind, type: kind === 'none' ? null : 'x', allowedHref: null, options: null, ...extra,
});

const FIELDS:FieldSchema[] = [
  {
    id: 'status',
    name: 'Status',
    operators: [op('=', 'list', { type: '[]Status', allowedHref: '/api/v3/statuses' }), op('*', 'none')],
  },
  { id: 'type', name: 'Type', operators: [op('=', 'list', { type: '[]Type', allowedHref: '/api/v3/types' })] },
  { id: 'cf', name: 'Option field', operators: [op('=', 'list', { type: '[]CustomOption', options: [{ id: '1', name: 'A' }] })] },
  { id: 'subject', name: 'Subject', operators: [op('~', 'text', { type: '[1]String' })] },
  { id: 'done', name: 'Done', operators: [op('=', 'boolean', { type: '[1]Boolean' })] },
  { id: 'due', name: 'Due', operators: [op('<>d', 'dates', { type: '[2]Date' }), op('=d', 'date', { type: '[1]Date' })] },
  { id: 'n', name: 'Number', operators: [op('=', 'number', { type: '[1]Integer' })] },
];

describe('WorkItemConditionRowComponent#valueInput', () => {
  let fields$:Observable<FieldSchema[]>;
  const allowed:Record<string, Observable<AllowedValues>> = {
    '/api/v3/statuses': of({ options: [{ id: '1', name: 'New' }], complete: true }),
    '/api/v3/types': of({ options: [], complete: false }), // truncated collection
  };

  beforeEach(() => {
    fields$ = of(FIELDS);
    TestBed.configureTestingModule({
      providers: [
        { provide: I18nService, useValue: { t: (key:string) => key } },
        {
          provide: WorkItemFilterSchemaService,
          useValue: { fields: () => fields$, allowedValues: (href:string) => allowed[href] ?? NEVER },
        },
      ],
    });
  });

  function valueInput(condition:Condition, invalid = false) {
    const fixture = TestBed.createComponent(WorkItemConditionRowComponent);
    fixture.componentRef.setInput('condition', condition);
    fixture.componentRef.setInput('invalid', invalid);
    fixture.detectChanges();
    return { kind: fixture.componentInstance.valueInput(), el: fixture.nativeElement as HTMLElement };
  }

  it('follows the operator kind', () => {
    expect(valueInput({ field: '', operator: '=', values: [] }).kind).toBe('none');
    expect(valueInput({ field: 'status', operator: '*', values: [] }).kind).toBe('none');
    expect(valueInput({ field: 'status', operator: '=', values: [] }).kind).toBe('list');
    expect(valueInput({ field: 'cf', operator: '=', values: [] }).kind).toBe('list');
    expect(valueInput({ field: 'subject', operator: '~', values: [] }).kind).toBe('text');
    expect(valueInput({ field: 'done', operator: '=', values: [] }).kind).toBe('boolean');
    expect(valueInput({ field: 'due', operator: '<>d', values: [] }).kind).toBe('dates');
    expect(valueInput({ field: 'due', operator: '=d', values: [] }).kind).toBe('date');
    expect(valueInput({ field: 'n', operator: '=', values: [] }).kind).toBe('number');
  });

  it('falls back to ids for truncated lists and for unknown operators that carry values', () => {
    expect(valueInput({ field: 'type', operator: '=', values: [] }).kind).toBe('ids');
    expect(valueInput({ field: 'status', operator: 'zz', values: ['3'] }).kind).toBe('ids');
    expect(valueInput({ field: 'status', operator: 'zz', values: [] }).kind).toBe('none');
  });

  it('shows a disabled placeholder (not the ids input) while the schema or the values load', () => {
    allowed['/api/v3/pending'] = NEVER;
    FIELDS.push({ id: 'pending', name: 'Pending', operators: [op('=', 'list', { type: '[]X', allowedHref: '/api/v3/pending' })] });
    expect(valueInput({ field: 'pending', operator: '=', values: [] }).kind).toBe('loading');
    FIELDS.pop();

    fields$ = NEVER;
    const { kind, el } = valueInput({ field: 'status', operator: '=', values: ['1'] });
    expect(kind).toBe('loading');
    expect(el.querySelector('input[disabled]')).not.toBeNull();
  });

  it('flags an incomplete clause with aria-invalid and an inline message', () => {
    const { el } = valueInput({ field: 'subject', operator: '~', values: [] }, true);
    const inputEl = el.querySelector('.values input')!;
    expect(inputEl.getAttribute('aria-invalid')).toBe('true');
    const message = el.querySelector(`#${inputEl.getAttribute('aria-describedby')}`);
    expect(message?.textContent).toContain('js.work_item_queries.errors.incomplete_clause');
  });

  it('clears the load error once the filter definitions load again', () => {
    fields$ = throwError(() => new Error('down'));
    const fixture = TestBed.createComponent(WorkItemConditionRowComponent);
    fixture.componentRef.setInput('condition', { field: '', operator: '=', values: [] });
    fixture.detectChanges();
    expect(fixture.componentInstance.loadError()).toBe(true);

    fields$ = of(FIELDS);
    fixture.componentRef.setInput('projectId', 3);
    fixture.detectChanges();
    expect(fixture.componentInstance.loadError()).toBe(false);
  });
});
