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
import { HttpErrorResponse, provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import {
  apiErrors, errorText, linkId, resolveProjectId, WorkItemQueryService,
} from './work-item-query.service';

describe('resolveProjectId', () => {
  it('uses no project for a new query on the global page', () => {
    expect(resolveProjectId(false, null, null)).toBeNull();
  });

  it("uses the page's project for a new query on a project page", () => {
    expect(resolveProjectId(false, null, 5)).toBe(5);
  });

  it("keeps a loaded query's own project when opened on another page", () => {
    expect(resolveProjectId(false, 3, 5)).toBe(3);
    expect(resolveProjectId(false, 3, null)).toBe(3);
  });

  it('uses no project when across projects is toggled on', () => {
    expect(resolveProjectId(true, 3, 5)).toBeNull();
    expect(resolveProjectId(true, null, 5)).toBeNull();
  });
});

describe('linkId', () => {
  it('reads the id at the end of a HAL link and null for an unset link', () => {
    expect(linkId({ href: '/sub/api/v3/projects/12', title: 'P' })).toBe(12);
    expect(linkId({ href: null })).toBeNull();
    expect(linkId(undefined)).toBeNull();
  });
});

describe('apiErrors / errorText', () => {
  const fail = (error:unknown, status = 422) => new HttpErrorResponse({ status, error });

  it('reads a single PropertyConstraintViolation with its attribute', () => {
    const err = fail({ message: 'Sharing needs a permission.', _embedded: { details: { attribute: 'public' } } });
    expect(apiErrors(err)).toEqual([{ message: 'Sharing needs a permission.', attribute: 'public' }]);
  });

  it('expands MultipleErrors and joins their messages', () => {
    const err = fail({
      message: 'Multiple field constraints have been violated.',
      _embedded: {
        errors: [
          { message: "Name can't be blank.", _embedded: { details: { attribute: 'name' } } },
          { message: 'Bad tree.', _embedded: { details: { attribute: 'tree' } } },
        ],
      },
    });
    expect(apiErrors(err).map((e) => e.attribute)).toEqual(['name', 'tree']);
    expect(errorText(err, 'x')).toBe("Name can't be blank. Bad tree.");
  });

  it('falls back when the body has no message', () => {
    expect(errorText(fail(null, 0), 'Save failed')).toBe('Save failed');
    expect(errorText(fail('<html>', 500), 'Save failed')).toBe('Save failed');
  });
});

describe('WorkItemQueryService', () => {
  let service:WorkItemQueryService;
  let http:HttpTestingController;

  beforeEach(() => {
    window.appBasePath = '/sub';
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
    service = TestBed.inject(WorkItemQueryService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    window.appBasePath = '';
  });

  it('requests the API under the app base path and unwraps the collection', () => {
    let names:string[] = [];
    service.list().subscribe((items) => { names = items.map((i) => i.name); });
    http.expectOne('/sub/api/v3/work_item_queries').flush({ _embedded: { elements: [{ id: 1, name: 'A' }] } });
    expect(names).toEqual(['A']);

    service.get(4).subscribe();
    http.expectOne('/sub/api/v3/work_item_queries/4').flush({});
    service.setFavorite(4, true).subscribe();
    http.expectOne({ method: 'PUT', url: '/sub/api/v3/work_item_queries/4/favorite' }).flush(null);
  });

  it('builds project hrefs under the base path', () => {
    expect(service.projectHref(7)).toBe('/sub/api/v3/projects/7');
    expect(service.projectHref(null)).toBeNull();
  });
});
