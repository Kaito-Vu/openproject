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

import {
  parseCollection, parseQueryForm, valueKind, valuesAfterOperatorChange,
} from './work-item-filter-schema';

const op = (sym:string, title:string) => ({ href: `/api/v3/queries/operators/${encodeURIComponent(sym)}`, title });

// Mirrors QueryFilterInstanceSchemaRepresenter rendered with form_embedded: true
// (spec/lib/api/v3/queries/schemas/query_filter_instance_schema_representer_spec.rb):
// filter/operator are "links to and embeds allowed values directly"; _dependencies[0].dependencies is
// keyed by the operator href (CGI-escaped symbol). Dependency values mirror FilterDependencyRepresenter:
// StatusFilterDependencyRepresenter ("links to allowed values via collection link"),
// CustomOptionFilterDependencyRepresenter ("links to allowed values directly"),
// DateFilterDependencyRepresenter ([1]Integer / [1]Date / [2]Date) and "filter dependency empty" ({}).
const statusSchema = {
  _type: 'QueryFilterInstanceSchema',
  filter: { type: 'QueryFilter', _links: { allowedValues: [{ href: '/api/v3/queries/filters/status', title: 'Status' }] } },
  operator: { type: 'QueryOperator', _links: { allowedValues: [op('o', 'open'), op('=', 'is'), op('*', 'all')] } },
  _dependencies: [{
    _type: 'SchemaDependency',
    on: 'operator',
    dependencies: {
      '/api/v3/queries/operators/o': {},
      '/api/v3/queries/operators/%3D': {
        values: {
          type: '[]Status', name: 'Values', required: true, hasDefault: false, writable: true,
          _links: { allowedValues: { href: '/api/v3/statuses' } },
        },
      },
      '/api/v3/queries/operators/*': {},
    },
  }],
};

const customFieldSchema = {
  filter: { _links: { allowedValues: [{ href: '/api/v3/queries/filters/customField12', title: 'Color' }] } },
  operator: { _links: { allowedValues: [op('=', 'is')] } },
  _dependencies: [{
    on: 'operator',
    dependencies: {
      '/api/v3/queries/operators/%3D': {
        values: {
          type: '[]CustomOption',
          _links: { allowedValues: [{ href: '/api/v3/custom_options/5', title: 'Red' }, { href: '/api/v3/custom_options/6', title: 'Blue' }] },
        },
      },
    },
  }],
};

const dueDateSchema = {
  filter: { _links: { allowedValues: [{ href: '/api/v3/queries/filters/dueDate', title: 'Finish date' }] } },
  operator: { _links: { allowedValues: [op('<t-', 'less than days ago'), op('=d', 'on'), op('<>d', 'between'), op('t', 'today')] } },
  _dependencies: [{
    on: 'operator',
    dependencies: {
      '/api/v3/queries/operators/%3Ct-': { values: { type: '[1]Integer' } },
      '/api/v3/queries/operators/%3Dd': { values: { type: '[1]Date' } },
      '/api/v3/queries/operators/%3C%3Ed': { values: { type: '[2]Date' } },
      '/api/v3/queries/operators/t': {},
    },
  }],
};

const form = { _embedded: { schema: { _embedded: { filtersSchemas: { _embedded: { elements: [statusSchema, customFieldSchema, dueDateSchema] } } } } } };

describe('parseQueryForm', () => {
  const fields = parseQueryForm(form);

  it('lists fields by name with their API ids', () => {
    expect(fields.map((f) => [f.id, f.name])).toEqual([['customField12', 'Color'], ['dueDate', 'Finish date'], ['status', 'Status']]);
  });

  it('decodes operator ids and reads the value schema per operator', () => {
    const status = fields.find((f) => f.id === 'status')!;
    expect(status.operators.map((o) => [o.id, o.kind])).toEqual([['o', 'none'], ['=', 'list'], ['*', 'none']]);
    expect(status.operators[1].allowedHref).toBe('/api/v3/statuses');
    expect(status.operators[1].options).toBe(null);
  });

  it('takes inline custom options as list options', () => {
    const cf = fields.find((f) => f.id === 'customField12')!;
    expect(cf.operators[0].options).toEqual([{ id: '5', name: 'Red' }, { id: '6', name: 'Blue' }]);
    expect(cf.operators[0].allowedHref).toBe(null);
  });

  it('maps date operators to number, date, date pair and none', () => {
    const due = fields.find((f) => f.id === 'dueDate')!;
    expect(due.operators.map((o) => [o.id, o.kind])).toEqual([['<t-', 'number'], ['=d', 'date'], ['<>d', 'dates'], ['t', 'none']]);
  });

  it('returns no fields for an unexpected payload', () => {
    expect(parseQueryForm({})).toEqual([]);
  });
});

describe('valueKind', () => {
  it('maps backend value types', () => {
    expect(['[1]Boolean', '[1]String', '[1]Float', '[1]DateTime', '[2]DateTime', '[]User', undefined].map(valueKind))
      .toEqual(['boolean', 'text', 'number', 'date', 'dates', 'list', 'none']);
  });
});

describe('parseCollection', () => {
  it('uses id and name, and reports truncated collections', () => {
    const res = { total: 3, count: 2, _embedded: { elements: [{ id: 1, name: 'New' }, { id: 2, subject: 'WP' }] } };
    expect(parseCollection(res)).toEqual({ options: [{ id: '1', name: 'New' }, { id: '2', name: 'WP' }], complete: false });
  });
});

describe('valuesAfterOperatorChange', () => {
  const fields = parseQueryForm(form);
  const status = fields.find((f) => f.id === 'status')!.operators;
  const due = fields.find((f) => f.id === 'dueDate')!.operators;

  it('keeps values when the value type is unchanged and resets otherwise', () => {
    expect(valuesAfterOperatorChange(due[1], due[1], ['2026-01-01'])).toEqual(['2026-01-01']);
    expect(valuesAfterOperatorChange(due[0], due[1], ['3'])).toEqual([]);
    expect(valuesAfterOperatorChange(status[0], status[2], ['1'])).toEqual([]);
  });
});
