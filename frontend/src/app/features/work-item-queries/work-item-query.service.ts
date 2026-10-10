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

import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { map, Observable } from 'rxjs';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { Group } from './work-item-query-tree';
import { ResultElement } from './work-item-columns';
import { idFromHref } from './work-item-filter-schema';

export type QueryMode = 'flat'|'tree';

interface HalLink { href:string|null; title?:string }

// WorkItemQueryRepresenter (HAL). The list's elements carry no `tree`; GET by id does.
export interface WorkItemQuery {
  id:number;
  name:string;
  mode:QueryMode;
  public:boolean;
  columns:string[];
  sortCriteria:[string, string][];
  tree?:Group;
  favorite:boolean;
  createdAt:string;
  updatedAt:string;
  _links:{ self:HalLink; project:HalLink; user:HalLink; updatedBy:HalLink };
}

// Body of POST/PATCH and /execute; omitted keys keep their stored value (PATCH) or the server default.
export interface WorkItemQueryPayload {
  name?:string;
  mode?:QueryMode;
  public?:boolean;
  columns?:string[];
  tree?:Group;
  _links?:{ project:{ href:string|null } };
}

export interface ExecuteResponse { _embedded:{ results:{ total?:number; _embedded:{ elements:ResultElement[] } } } }

// Numeric id at the end of a HAL link, or null for an unset link (e.g. a global query's project).
export function linkId(link:HalLink|undefined):number|null {
  return link?.href ? Number(idFromHref(link.href)) : null;
}

// Project a query runs and saves in: none when "Query across projects" is checked, otherwise the
// loaded query's own project, falling back to the page's project (new query, or a loaded global one).
export function resolveProjectId(acrossProjects:boolean, queryProjectId:number|null, pageProjectId:number|null):number|null {
  return acrossProjects ? null : (queryProjectId ?? pageProjectId);
}

export interface ApiError { message:string; attribute:string|null }

interface ErrorBody { message?:string; _embedded?:{ details?:{ attribute?:string }; errors?:ErrorBody[] } }

// The API v3 error(s) in a failed response: one entry per violation (MultipleErrors are expanded).
export function apiErrors(err:HttpErrorResponse):ApiError[] {
  const body = err.error as ErrorBody|null;
  if (!body || typeof body !== 'object') { return []; }
  const nested = body._embedded?.errors;
  const list = nested?.length ? nested : [body];
  return list
    .filter((e) => e.message)
    .map((e) => ({ message: e.message!, attribute: e._embedded?.details?.attribute ?? null }));
}

// All messages of a failed response, or the fallback when the body has none (network error, 500).
export function errorText(err:HttpErrorResponse, fallback:string):string {
  return apiErrors(err).map((e) => e.message).join(' ') || fallback;
}

@Injectable({ providedIn: 'root' })
export class WorkItemQueryService {
  private http = inject(HttpClient);

  private apiV3Base = inject(PathHelperService).api.v3.apiV3Base;

  private base = `${this.apiV3Base}/work_item_queries`;

  projectHref(projectId:number|null):string|null {
    return projectId == null ? null : `${this.apiV3Base}/projects/${projectId}`;
  }

  list():Observable<WorkItemQuery[]> {
    return this.http.get<{ _embedded:{ elements:WorkItemQuery[] } }>(this.base).pipe(map((res) => res._embedded.elements));
  }

  get(id:number):Observable<WorkItemQuery> { return this.http.get<WorkItemQuery>(`${this.base}/${id}`); }

  execute(body:WorkItemQueryPayload&{ pageSize?:number }):Observable<ExecuteResponse> {
    return this.http.post<ExecuteResponse>(`${this.base}/execute`, body);
  }

  create(body:WorkItemQueryPayload):Observable<WorkItemQuery> { return this.http.post<WorkItemQuery>(this.base, body); }

  update(id:number, body:WorkItemQueryPayload):Observable<WorkItemQuery> {
    return this.http.patch<WorkItemQuery>(`${this.base}/${id}`, body);
  }

  setFavorite(id:number, on:boolean):Observable<void> {
    const url = `${this.base}/${id}/favorite`;
    return on ? this.http.put<void>(url, {}) : this.http.delete<void>(url);
  }

  remove(id:number):Observable<void> { return this.http.delete<void>(`${this.base}/${id}`); }
}
