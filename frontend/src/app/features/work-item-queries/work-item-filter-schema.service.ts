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
import { catchError, map, Observable, shareReplay, throwError } from 'rxjs';
import { AllowedValues, FieldSchema, parseCollection, parseQueryForm } from './work-item-filter-schema';

// Caches per page: one query form request for all fields, one request per allowed-values collection.
// Failed requests are dropped from the cache so the next row retries.
@Injectable({ providedIn: 'root' })
export class WorkItemFilterSchemaService {
  private http = inject(HttpClient);

  private fields$?:Observable<FieldSchema[]>;

  private allowed = new Map<string, Observable<AllowedValues>>();

  // ponytail: global (project-less) filter set; scope by project via _links.project in the body if needed.
  fields():Observable<FieldSchema[]> {
    this.fields$ ??= this.http.post<unknown>('/api/v3/queries/form', {}).pipe(
      map(parseQueryForm),
      shareReplay(1),
      catchError((err:unknown) => { this.fields$ = undefined; return throwError(() => err); }),
    );
    return this.fields$;
  }

  allowedValues(href:string):Observable<AllowedValues> {
    let req = this.allowed.get(href);
    if (!req) {
      req = this.http.get<unknown>(href).pipe(
        map(parseCollection),
        shareReplay(1),
        catchError((err:unknown) => { this.allowed.delete(href); return throwError(() => err); }),
      );
      this.allowed.set(href, req);
    }
    return req;
  }
}
