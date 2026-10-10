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
import { of } from 'rxjs';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { ToastService } from 'core-app/shared/components/toaster/toast.service';
import { TimezoneService } from 'core-app/core/datetime/timezone.service';
import { WorkItemQueryEditorComponent } from './work-item-query-editor.component';
import { WorkItemFilterSchemaService } from './work-item-filter-schema.service';
import { FieldSchema } from './work-item-filter-schema';
import { Condition } from './work-item-query-tree';

const FIELDS:FieldSchema[] = [{
  id: 'status',
  name: 'Status',
  operators: [
    { id: '=', name: 'is', kind: 'list', type: '[]Status', allowedHref: null, options: [{ id: '1', name: 'New' }] },
    { id: '*', name: 'any', kind: 'none', type: null, allowedHref: null, options: null },
  ],
}];

const API = '/sub/api/v3/work_item_queries';
const EDITOR_URL = '/sub/projects/demo/queries/editor';

const savedQuery = (over:Record<string, unknown> = {}) => ({
  id: 7,
  name: 'Open bugs',
  mode: 'flat',
  public: false,
  columns: ['id', 'subject'],
  sortCriteria: [['id', 'asc']],
  tree: { op: 'and', children: [{ field: 'status', operator: '=', values: ['1'] }] },
  favorite: false,
  createdAt: '2026-10-10T07:39:16.016Z',
  updatedAt: '2026-10-10T07:39:16.016Z',
  _links: {
    self: { href: `${API}/7` },
    project: { href: '/sub/api/v3/projects/5', title: 'Demo' },
    user: { href: '/sub/api/v3/users/1' },
    updatedBy: { href: '/sub/api/v3/users/1' },
  },
  ...over,
});

const executeResponse = { _embedded: { results: { total: 0, _embedded: { elements: [] } } } };

describe('WorkItemQueryEditorComponent', () => {
  let http:HttpTestingController;
  let toast:{ addSuccess:ReturnType<typeof vi.fn> };

  function create(inputs:{ queryId?:number } = {}) {
    const fixture = TestBed.createComponent(WorkItemQueryEditorComponent);
    const editor = fixture.componentInstance;
    editor.projectId = 5;
    editor.queryId = inputs.queryId ?? null;
    editor.listUrl = '/sub/projects/demo/queries';
    editor.editorUrl = EDITOR_URL;
    fixture.detectChanges();
    return { fixture, editor };
  }

  // Makes the starter clause "Status is New".
  function completeFirstClause(editor:WorkItemQueryEditorComponent):void {
    editor.update([0], { field: 'status', operator: '=', values: ['1'] });
  }

  beforeEach(() => {
    window.appBasePath = '/sub';
    toast = { addSuccess: vi.fn() };
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: I18nService, useValue: { t: (key:string) => key } },
        { provide: ToastService, useValue: toast },
        { provide: TimezoneService, useValue: { formattedDate: (v:string) => v, formattedDatetime: (v:string) => v } },
        {
          provide: WorkItemFilterSchemaService,
          useValue: { fields: () => of(FIELDS), allowedValues: () => of({ options: [], complete: true }) },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    window.appBasePath = '';
    vi.restoreAllMocks();
  });

  it('creates a query with a camelCase HAL body, then rewrites the URL under the injected base path', () => {
    const replaceState = vi.spyOn(window.history, 'replaceState').mockImplementation(() => undefined);
    const { editor } = create();
    completeFirstClause(editor);
    editor.setName(' Open bugs ');
    expect(editor.dirty()).toBe(true);

    editor.save();
    const req = http.expectOne({ method: 'POST', url: API });
    expect(req.request.body).toEqual({
      name: 'Open bugs',
      mode: 'flat',
      public: false,
      columns: ['id', 'type', 'subject', 'status', 'assignee'],
      tree: { op: 'and', children: [{ field: 'status', operator: '=', values: ['1'] }] },
      _links: { project: { href: '/sub/api/v3/projects/5' } },
    });
    expect(JSON.stringify(req.request.body)).not.toContain('key');
    expect(editor.saving()).toBe(true);

    req.flush(savedQuery());
    expect(replaceState).toHaveBeenCalledWith(null, '', `${EDITOR_URL}?id=7`);
    expect(toast.addSuccess).toHaveBeenCalledWith('js.notice_successful_create');
    expect(editor.currentId()).toBe(7);
    expect(editor.dirty()).toBe(false);
    expect(editor.saving()).toBe(false);
  });

  it('updates an existing query with PATCH and does not touch the URL', () => {
    const replaceState = vi.spyOn(window.history, 'replaceState').mockImplementation(() => undefined);
    const { editor } = create({ queryId: 7 });
    http.expectOne(`${API}/7`).flush(savedQuery());
    http.expectOne(`${API}/execute`).flush(executeResponse);

    editor.setName('Renamed');
    editor.save();
    http.expectOne({ method: 'PATCH', url: `${API}/7` }).flush(savedQuery({ name: 'Renamed' }));
    expect(replaceState).not.toHaveBeenCalled();
    expect(toast.addSuccess).toHaveBeenCalledWith('js.notice_successful_update');
  });

  it('handles a 422 on `public` by unticking and disabling Shared', () => {
    const { editor } = create();
    completeFirstClause(editor);
    editor.setName('Shared');
    editor.isPublic.set(true);

    editor.save();
    http.expectOne({ method: 'POST', url: API }).flush(
      {
        _type: 'Error',
        errorIdentifier: 'urn:openproject-org:api:v3:errors:PropertyConstraintViolation',
        message: 'Sharing with everyone requires the permission to manage public queries.',
        _embedded: { details: { attribute: 'public' } },
      },
      { status: 422, statusText: 'Unprocessable Content' },
    );
    expect(editor.publicDenied()).toBe(true);
    expect(editor.isPublic()).toBe(false);
    expect(editor.error()).toBe('Sharing with everyone requires the permission to manage public queries.');
  });

  it('does not treat other failures as a sharing denial', () => {
    const { editor } = create();
    completeFirstClause(editor);
    editor.setName('Shared');
    editor.isPublic.set(true);
    editor.save();
    http.expectOne({ method: 'POST', url: API }).flush({ message: 'No permission.' }, { status: 403, statusText: 'Forbidden' });
    expect(editor.publicDenied()).toBe(false);
    expect(editor.isPublic()).toBe(true);
    expect(editor.error()).toBe('No permission.');
  });

  it('shows the server message when a run fails and clears the results', () => {
    const { editor } = create();
    completeFirstClause(editor);
    editor.run();
    expect(editor.running()).toBe(true);
    expect(editor.announcement()).toBe('js.work_item_queries.editor.running');
    http.expectOne(`${API}/execute`).flush(
      { message: 'invalid condition on nope', _embedded: { details: { attribute: 'tree' } } },
      { status: 422, statusText: 'Unprocessable Content' },
    );
    expect(editor.running()).toBe(false);
    expect(editor.error()).toBe('invalid condition on nope');
    expect(editor.ran()).toBe(false);
    expect(editor.results()).toEqual([]);
  });

  it('marks results stale after an edit', () => {
    const { editor } = create();
    completeFirstClause(editor);
    editor.run();
    http.expectOne(`${API}/execute`).flush(executeResponse);
    expect(editor.stale()).toBe(false);
    editor.mode.set('tree');
    expect(editor.stale()).toBe(true);
  });

  it('blocks Run and Save while a clause lacks its values and flags that clause', () => {
    const { editor } = create();
    editor.update([0], { field: 'status', operator: '=', values: [] });
    editor.setName('x');
    editor.run();
    editor.save();
    http.expectNone(`${API}/execute`);
    http.expectNone(API);
    expect(editor.showInvalid()).toBe(true);
    expect(editor.error()).toBe('js.work_item_queries.errors.incomplete_clauses');
    const key = (editor.tree().children[0] as Condition).key!;
    expect(editor.incompleteKeys().has(key)).toBe(true);

    editor.update([0], { operator: '*' }); // "any" takes no values
    expect(editor.incompleteKeys().size).toBe(0);
  });

  it('tracks unsaved changes against the baseline and reverts all fields after confirmation', () => {
    const confirm = vi.spyOn(window, 'confirm');
    const { editor } = create();
    expect(editor.dirty()).toBe(false);
    editor.add(); // blank clauses are not a change
    expect(editor.dirty()).toBe(false);

    completeFirstClause(editor);
    editor.setName('Draft');
    editor.columns.set(['id']);
    expect(editor.dirty()).toBe(true);

    confirm.mockReturnValue(false);
    editor.revert();
    expect(editor.name()).toBe('Draft');

    confirm.mockReturnValue(true);
    editor.revert();
    expect(editor.name()).toBe('');
    expect(editor.columns()).toEqual(['id', 'type', 'subject', 'status', 'assignee']);
    expect(editor.dirty()).toBe(false);
  });

  it('asks before leaving the page only when dirty', () => {
    const { editor } = create();
    const clean = new Event('beforeunload', { cancelable: true }) as BeforeUnloadEvent;
    editor.onBeforeUnload(clean);
    expect(clean.defaultPrevented).toBe(false);

    editor.setName('Draft');
    const dirty = new Event('beforeunload', { cancelable: true }) as BeforeUnloadEvent;
    editor.onBeforeUnload(dirty);
    expect(dirty.defaultPrevented).toBe(true);
  });

  it('shows a loading state for an existing query, then loads it by id and runs it', () => {
    const { editor, fixture } = create({ queryId: 7 });
    expect(editor.status()).toBe('loading');
    expect(fixture.nativeElement.querySelector('.wiq-title')).toBeNull();

    http.expectOne(`${API}/7`).flush(savedQuery());
    expect(editor.status()).toBe('ready');
    expect(editor.name()).toBe('Open bugs');
    expect(editor.dirty()).toBe(false);
    const run = http.expectOne(`${API}/execute`);
    expect(run.request.body._links).toEqual({ project: { href: '/sub/api/v3/projects/5' } });
    run.flush(executeResponse);
  });

  it('keeps the form hidden and Save inert when loading fails', () => {
    const { editor, fixture } = create({ queryId: 7 });
    http.expectOne(`${API}/7`).flush({ message: 'Not found.' }, { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();
    expect(editor.status()).toBe('failed');
    expect(editor.error()).toBe('Not found.');
    expect(fixture.nativeElement.querySelector('.wiq-title')).toBeNull();
    editor.save();
    http.expectNone(API);
  });

  it('renders a group header row with its ops editable and enables Group only for groupable selections', () => {
    const { editor, fixture } = create();
    completeFirstClause(editor);
    editor.add();
    editor.add();
    editor.toggleSelected([0], true);
    editor.toggleSelected([2], true);
    expect(editor.canGroup()).toBe(false);
    editor.toggleSelected([2], false);
    editor.toggleSelected([1], true);
    expect(editor.canGroup()).toBe(true);
    editor.group();
    fixture.detectChanges();

    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelectorAll('[data-test-selector="wiq-group-row"]').length).toBe(1);
    expect(el.querySelectorAll('[data-test-selector="wiq-clause-row"]').length).toBe(3);
    // [group(A, B), C]: the group's op sits on B, the root op on C.
    expect(el.querySelectorAll('.wiq-andor select').length).toBe(2);
  });
});
