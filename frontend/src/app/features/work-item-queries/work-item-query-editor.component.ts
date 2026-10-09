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

import { HttpErrorResponse } from '@angular/common/http';
import { finalize, Subscription } from 'rxjs';
import { Component, ElementRef, Input, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';
import {
  addCondition, Condition, emptyTree, group, Group, Path, removeAt, Row, rows, setOp, ungroup, updateCondition,
} from './work-item-query-tree';
import {
  applySaved, buildSavePayload, resolveProjectId, WorkItemQueryItem, WorkItemQueryService,
} from './work-item-query.service';
import { toCsv } from './work-item-csv';
import { copyText } from './work-item-copy-text';
import { COLUMN_CATALOG, DEFAULT_COLUMNS, toggleColumn } from './work-item-columns';
import { ResultRow, WorkItemResultsComponent } from './work-item-results.component';
import { WorkItemConditionRowComponent } from './work-item-condition-row.component';

// Replaces characters invalid in file names (and control chars) with underscores.
function safeFileName(name:string):string {
  const clean = [...name].map((c) => (c.charCodeAt(0) < 32 || '/\\:*?"<>|'.includes(c) ? '_' : c)).join('').trim();
  return clean || 'query';
}

function errorMessage(err:HttpErrorResponse, fallback:string):string {
  return (err.error as { message?:string }|null)?.message ?? fallback;
}

@Component({
  selector: 'op-work-item-query-editor',
  standalone: true,
  imports: [FormsModule, WorkItemResultsComponent, WorkItemConditionRowComponent],
  templateUrl: './work-item-query-editor.component.html',
})
export class WorkItemQueryEditorComponent implements OnInit, OnDestroy {
  @Input() projectId:number|null = null;

  @Input() queryId:number|null = null;

  readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);

  private service = inject(WorkItemQueryService);

  // Signals: the app is zoneless, so state changed in HTTP callbacks must notify the view itself.
  readonly tree = signal<Group>(emptyTree());

  readonly mode = signal<'flat'|'tree'>('flat');

  readonly acrossProjects = signal(false);

  readonly columns = signal<string[]>(DEFAULT_COLUMNS);

  readonly showColumns = signal(false);

  readonly catalog = COLUMN_CATALOG;

  readonly isPublic = signal(false);

  // Set when the API refused to share with everyone (missing manage_public_queries).
  readonly publicDenied = signal(false);

  readonly results = signal<ResultRow[]>([]);

  readonly error = signal<string|null>(null);

  readonly selected = signal(new Set<string>());

  readonly currentId = signal<number|null>(null);

  readonly name = signal('');

  readonly copyState = signal<'idle'|'copied'|'failed'>('idle');

  private copyTimer?:ReturnType<typeof setTimeout>;

  readonly loading = signal(false);

  readonly saving = signal(false);

  private loadToken = 0;

  private subs:Partial<Record<'load'|'run'|'save', Subscription>> = {};

  readonly total = signal(0);

  // The saved query being edited (as last loaded or saved); null for a new query.
  readonly loaded = signal<WorkItemQueryItem|null>(null);

  // projectId is a plain input but is fixed once the constructor has read the dataset.
  readonly queryProjectId = computed(() => resolveProjectId(this.acrossProjects(), this.loaded(), this.projectId));

  // Neither the query nor the page has a project: it can only run across projects.
  readonly hasOwnProject = computed(() => resolveProjectId(false, this.loaded(), this.projectId) != null);

  constructor() {
    populateInputsFromDataset(this);
  }

  ngOnInit():void {
    this.acrossProjects.set(this.projectId == null);
    if (this.queryId == null) { return; }
    this.subs.load = this.service.get(Number(this.queryId)).subscribe({
      next: (item) => { this.load(item); this.run(); },
      error: (err:HttpErrorResponse) => { this.error.set(errorMessage(err, 'Loading the query failed')); },
    });
  }

  private destroyed = false;

  ngOnDestroy():void {
    this.destroyed = true;
    clearTimeout(this.copyTimer);
    Object.values(this.subs).forEach((sub) => sub?.unsubscribe());
  }

  get listUrl():string { return this.projectId ? `/projects/${this.projectId}/queries` : '/queries'; }

  get editorPath():string { return `${this.listUrl}/editor`; }

  exportCsv():void {
    const url = URL.createObjectURL(new Blob([toCsv(this.results(), this.columns())], { type: 'text/csv;charset=utf-8' }));
    const a = document.createElement('a');
    a.href = url;
    a.download = `${safeFileName(this.name())}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => { URL.revokeObjectURL(url); }, 1000);
  }

  copyUrl():void {
    const id = this.currentId();
    if (id == null) { return; }
    const done = (state:'copied'|'failed'):void => {
      if (this.destroyed) { return; }
      this.copyState.set(state);
      clearTimeout(this.copyTimer);
      this.copyTimer = setTimeout(() => { this.copyState.set('idle'); }, 2000);
    };
    void copyText((navigator as { clipboard?:Clipboard }).clipboard, `${window.location.origin}${this.editorPath}?id=${id}`).then(done);
  }

  get rows():Row[] { return rows(this.tree()); }

  run():void {
    this.subs.run?.unsubscribe(); // last request wins; finalize resets loading before we set it again
    this.loading.set(true);
    this.error.set(null);
    this.subs.run = this.service
      .execute({
        tree: this.tree(), mode: this.mode(), project_id: this.queryProjectId(), columns: this.columns(), pageSize: 500,
      })
      .pipe(finalize(() => { this.loading.set(false); }))
      .subscribe({
        next: (res) => {
          this.total.set(res._embedded.results.total ?? 0);
          this.results.set(res._embedded.results._embedded.elements.map((element) => {
            const parentHref = element._links.parent?.href;
            return {
              id: element.id, parentId: parentHref ? Number(parentHref.split('/').pop()) : null, element, children: [],
            };
          }));
        },
        error: (err:HttpErrorResponse) => {
          this.results.set([]);
          this.total.set(0);
          this.error.set(errorMessage(err, 'Query failed'));
        },
      });
  }

  add():void { this.tree.update((t) => addCondition(t, [])); }

  remove(path:Path):void {
    this.tree.update((t) => removeAt(t, path));
    this.selected.set(new Set());
  }

  update(path:Path, patch:Partial<Condition>):void { this.tree.update((t) => updateCondition(t, path, patch)); }

  toggleSelected(path:Path, checked:boolean):void {
    const key = path.join('.');
    this.selected.update((prev) => {
      const next = new Set(prev);
      if (checked) { next.add(key); } else { next.delete(key); }
      return next;
    });
  }

  toggleColumn(id:string, on:boolean):void { this.columns.update((cols) => toggleColumn(cols, id, on)); }

  group():void {
    this.tree.update((t) => group(t, [...this.selected()].map((s) => s.split('.').map(Number))));
    this.selected.set(new Set());
  }

  ungroup(path:Path):void {
    this.tree.update((t) => ungroup(t, path));
    this.selected.set(new Set());
  }

  toggleOp(row:Row):void { this.tree.update((t) => setOp(t, row.parentPath, row.parentOp === 'and' ? 'or' : 'and')); }

  save():void {
    if (this.saving()) { return; }
    const name = this.name() || (window.prompt('Query name') ?? '');
    if (!name) { return; }
    const loaded = this.loaded();
    const item = buildSavePayload(
      {
        name,
        mode: this.mode(),
        project_id: this.queryProjectId(),
        tree: this.tree(),
        public: this.isPublic(),
        columns: this.columns(),
      },
      loaded,
    );
    this.saving.set(true);
    const token = this.loadToken;
    const id = this.currentId();
    const req = id != null ? this.service.update(id, item) : this.service.create(item);
    this.subs.save = req.pipe(finalize(() => { this.saving.set(false); })).subscribe({
      next: (saved) => {
        const next = applySaved(
          { currentId: this.currentId(), lastLoaded: this.loaded(), loadToken: this.loadToken, name: this.name() }, token, saved,
        );
        this.name.set(next.name);
        const wasNew = this.currentId() == null;
        this.currentId.set(next.currentId);
        if (wasNew && next.currentId != null) {
          window.history.replaceState(null, '', `${this.editorPath}?id=${next.currentId}`);
        }
        this.loaded.set(next.lastLoaded);
      },
      error: (err:HttpErrorResponse) => {
        if (err.status === 403 && item.public && !loaded?.public) {
          this.publicDenied.set(true);
          this.isPublic.set(false);
        }
        this.error.set(errorMessage(err, 'Save failed'));
      },
    });
  }

  load(item:WorkItemQueryItem):void {
    this.loadToken += 1;
    this.loaded.set(item);
    this.currentId.set(item.id ?? null);
    this.name.set(item.name);
    this.mode.set(item.mode);
    this.acrossProjects.set(item.project_id == null);
    this.columns.set([...item.columns]);
    this.isPublic.set(item.public);
    this.tree.set(structuredClone(item.tree));
    this.selected.set(new Set());
  }

  revert():void {
    const loaded = this.loaded();
    if (loaded) { this.load(loaded); }
  }
}
