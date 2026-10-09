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

// Pure parsing of the query form's filter schemas (POST /api/v3/queries/form, which renders them
// with form_embedded: true; the standalone filter_instance_schemas endpoint omits allowed values).

export type ValueKind = 'none'|'list'|'text'|'number'|'date'|'dates'|'boolean';

export interface Option { id:string; name:string }

export interface OperatorSchema {
  id:string;
  name:string;
  kind:ValueKind;
  type:string|null; // e.g. "[]Status", "[1]Date"; null when the operator takes no values
  allowedHref:string|null; // collection to load list options from
  options:Option[]|null; // list options given inline (custom field options)
}

export interface FieldSchema { id:string; name:string; operators:OperatorSchema[] }

export interface AllowedValues { options:Option[]; complete:boolean }

interface Link { href?:string|null; title?:string }
interface ValuesSchema { type?:string; _links?:{ allowedValues?:Link|Link[] } }
interface InstanceSchema {
  filter?:{ _links?:{ allowedValues?:Link[] } };
  operator?:{ _links?:{ allowedValues?:Link[] } };
  _dependencies?:{ dependencies?:Record<string, { values?:ValuesSchema }> }[];
}

export const idFromHref = (href:string):string => decodeURIComponent(href.split('?')[0].split('/').pop() ?? '');

export function valueKind(type:string|null|undefined):ValueKind {
  if (!type) { return 'none'; }
  if (type.startsWith('[]')) { return 'list'; }
  // DateTime filters take plain dates too: the backend parses them as midnight UTC.
  if (type.startsWith('[2]Date')) { return 'dates'; }
  if (type.includes('Date')) { return 'date'; }
  if (type.includes('Integer') || type.includes('Float')) { return 'number'; }
  if (type.includes('Boolean')) { return 'boolean'; }
  return 'text';
}

function parseOperator(link:Link, deps:Record<string, { values?:ValuesSchema }>):OperatorSchema {
  const href = link.href ?? '';
  const values = deps[href]?.values;
  const allowed = values?._links?.allowedValues;
  const type = values?.type ?? null;
  return {
    id: idFromHref(href),
    name: link.title ?? idFromHref(href),
    kind: valueKind(type),
    type,
    allowedHref: allowed && !Array.isArray(allowed) ? allowed.href ?? null : null,
    options: Array.isArray(allowed) ? allowed.map((l) => ({ id: idFromHref(l.href ?? ''), name: l.title ?? '' })) : null,
  };
}

// Body for POST /api/v3/queries/form; without a project the form only knows global filters.
export function queryFormBody(projectId:number|null):object {
  return projectId == null ? {} : { _links: { project: { href: `/api/v3/projects/${projectId}` } } };
}

export function parseQueryForm(form:unknown):FieldSchema[] {
  const f = form as { _embedded?:{ schema?:{ _embedded?:{ filtersSchemas?:{ _embedded?:{ elements?:InstanceSchema[] } } } } } };
  const elements = f._embedded?.schema?._embedded?.filtersSchemas?._embedded?.elements ?? [];
  return elements
    .map((el) => {
      const filter = el.filter?._links?.allowedValues?.[0];
      const deps = el._dependencies?.[0]?.dependencies ?? {};
      return {
        id: idFromHref(filter?.href ?? ''),
        name: filter?.title ?? '',
        operators: (el.operator?._links?.allowedValues ?? []).map((l) => parseOperator(l, deps)),
      };
    })
    .filter((field) => field.id && field.operators.length)
    .sort((a, b) => a.name.localeCompare(b.name));
}

interface Element { id?:string|number; name?:string; label?:string; subject?:string; value?:string; _links?:{ self?:Link } }

export function parseCollection(res:unknown):AllowedValues {
  const c = res as { total?:number; _embedded?:{ elements?:Element[] } };
  const elements = c._embedded?.elements ?? [];
  return {
    options: elements.map((el) => {
      const id = el.id != null ? String(el.id) : idFromHref(el._links?.self?.href ?? '');
      return { id, name: el.name ?? el.label ?? el.subject ?? el.value ?? id };
    }),
    complete: c.total == null || c.total <= elements.length,
  };
}

// Values survive an operator change only when the value type stays the same.
export function valuesAfterOperatorChange(from:OperatorSchema|undefined, to:OperatorSchema|undefined, values:string[]):string[] {
  return from?.type && from.type === to?.type ? values : [];
}

// User lists offer "me" first (as the WP filter UI does), and saved values missing from the options
// (e.g. "me", deleted or locked users) stay listed by id so editing other values keeps them.
export function withSavedValues(options:Option[], type:string|null, saved:string[], meLabel:string):Option[] {
  const base = type?.includes('User') ? [{ id: 'me', name: meLabel }, ...options.filter((o) => o.id !== 'me')] : options;
  const known = new Set(base.map((o) => o.id));
  return [...base, ...saved.filter((v) => !known.has(v)).map((id) => ({ id, name: id }))];
}
