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
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { WorkItemFilterSchemaService } from './work-item-filter-schema.service';

describe('WorkItemFilterSchemaService#fields', () => {
  let service:WorkItemFilterSchemaService;
  let http:HttpTestingController;
  const emptyForm = { _embedded: { schema: { _embedded: { filtersSchemas: { _embedded: { elements: [] } } } } } };

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    service = TestBed.inject(WorkItemFilterSchemaService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => { http.verify(); });

  it('posts an empty body without a project and scopes the form to a project when given', () => {
    service.fields().subscribe();
    service.fields(5).subscribe();
    const reqs = http.match('/api/v3/queries/form');
    expect(reqs.map((r) => r.request.body)).toEqual([{}, { _links: { project: { href: '/api/v3/projects/5' } } }]);
    reqs.forEach((r) => { r.flush(emptyForm); });
  });

  it('caches the form per project', () => {
    service.fields(5).subscribe();
    service.fields(5).subscribe();
    service.fields(null).subscribe();
    expect(http.match('/api/v3/queries/form').length).toBe(2);
  });
});
