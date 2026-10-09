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

import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { Group } from './work-item-query-tree';

export interface WorkItemQueryItem {
  id?:number; name:string; mode:'flat'|'tree'; public:boolean; project_id:number|null;
  columns:string[]; sort_criteria:string[][]; tree:Group;
  user_id?:number; favorite?:boolean; updated_at?:string; updated_by_name?:string;
}

export interface EditorState {
  name:string; mode:'flat'|'tree'; project_id:number|null; tree:Group;
}

// New queries get defaults; existing ones keep public/columns/sort_criteria from the loaded item.
export function buildSavePayload(state:EditorState, loaded:WorkItemQueryItem|null):WorkItemQueryItem {
  return {
    name: state.name,
    mode: state.mode,
    project_id: state.project_id,
    tree: state.tree,
    public: loaded?.public ?? false,
    columns: loaded?.columns ?? ['id', 'type', 'subject', 'status', 'assignee'],
    sort_criteria: loaded?.sort_criteria ?? [['id', 'asc']],
  };
}

export interface SaveState { currentId:number|null; lastLoaded:WorkItemQueryItem|null; loadToken:number }

// Ignore a save response if the editor loaded another query since the save was clicked.
export function applySaved(state:SaveState, tokenAtClick:number, saved:WorkItemQueryItem):SaveState {
  if (state.loadToken !== tokenAtClick) { return state; }
  return { ...state, currentId: saved.id ?? state.currentId, lastLoaded: saved };
}

export interface ExecuteElement {
  id:number; subject:string;
  _links:{ type:{ title:string }; status:{ title:string }; assignee?:{ title:string }; parent?:{ href:string|null } };
}
export interface ExecuteResponse { _embedded:{ results:{ total?:number; _embedded:{ elements:ExecuteElement[] } } } }

@Injectable({ providedIn: 'root' })
export class WorkItemQueryService {
  private http = inject(HttpClient);

  private base = '/api/v3/work_item_queries';

  list():Observable<{ items:WorkItemQueryItem[] }> { return this.http.get<{ items:WorkItemQueryItem[] }>(this.base); }

  execute(body:Partial<WorkItemQueryItem>&{ pageSize?:number }):Observable<ExecuteResponse> {
    return this.http.post<ExecuteResponse>(`${this.base}/execute`, body);
  }

  create(item:WorkItemQueryItem):Observable<WorkItemQueryItem> { return this.http.post<WorkItemQueryItem>(this.base, item); }

  update(id:number, patch:Partial<WorkItemQueryItem>):Observable<WorkItemQueryItem> {
    return this.http.patch<WorkItemQueryItem>(`${this.base}/${id}`, patch);
  }

  setFavorite(id:number, on:boolean):Observable<void> {
    const url = `${this.base}/${id}/favorite`;
    return on ? this.http.put<void>(url, {}) : this.http.delete<void>(url);
  }

  remove(id:number):Observable<void> { return this.http.delete<void>(`${this.base}/${id}`); }
}
