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
import { Component, ElementRef, Input, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';
import {
  addCondition, Condition, emptyTree, group, Group, Path, removeAt, Row, rows, setOp, ungroup, updateCondition,
} from './work-item-query-tree';
import { applySaved, buildSavePayload, WorkItemQueryItem, WorkItemQueryService } from './work-item-query.service';
import { toCsv } from './work-item-csv';
import { copyText } from './work-item-copy-text';
import { ResultRow, WorkItemResultsComponent } from './work-item-results.component';
import { WorkItemConditionRowComponent } from './work-item-condition-row.component';

// Replaces characters invalid in file names (and control chars) with underscores.
function safeFileName(name:string):string {
  const clean = [...name].map((c) => (c.charCodeAt(0) < 32 || '/\\:*?"<>|'.includes(c) ? '_' : c)).join('').trim();
  return clean || 'query';
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

  readonly results = signal<ResultRow[]>([]);

  readonly error = signal<string|null>(null);

  saved:WorkItemQueryItem[] = [];

  readonly selected = signal(new Set<string>());

  readonly currentId = signal<number|null>(null);

  readonly name = signal('');

  readonly copyState = signal<'idle'|'copied'|'failed'>('idle');

  private copyTimer?:ReturnType<typeof setTimeout>;

  readonly loading = signal(false);

  readonly saving = signal(false);

  private loadToken = 0;

  private runSub?:Subscription;

  readonly total = signal(0);

  private lastLoaded:WorkItemQueryItem|null = null;

  constructor() {
    populateInputsFromDataset(this);
  }

  ngOnInit():void {
    this.service.list().subscribe({
      next: (res) => {
        this.saved = res.items;
        const preset = this.queryId != null ? res.items.find((i) => i.id === Number(this.queryId)) : undefined;
        if (preset) { this.load(preset); this.run(); }
      },
      error: (err:HttpErrorResponse) => { this.error.set((err.error as { message?:string }|null)?.message ?? 'Loading queries failed'); },
    });
  }

  private destroyed = false;

  ngOnDestroy():void { this.destroyed = true; clearTimeout(this.copyTimer); }

  get listUrl():string { return this.projectId ? `/projects/${this.projectId}/queries` : '/queries'; }

  get editorPath():string { return `${this.listUrl}/editor`; }

  exportCsv():void {
    const url = URL.createObjectURL(new Blob([toCsv(this.results())], { type: 'text/csv;charset=utf-8' }));
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
    this.runSub?.unsubscribe(); // last request wins; finalize resets loading before we set it again
    this.loading.set(true);
    this.error.set(null);
    this.runSub = this.service
      .execute({ tree: this.tree(), mode: this.mode(), project_id: this.acrossProjects() ? null : this.projectId, pageSize: 500 })
      .pipe(finalize(() => { this.loading.set(false); }))
      .subscribe({
        next: (res) => {
          this.total.set(res._embedded.results.total ?? 0);
          this.results.set(res._embedded.results._embedded.elements.map((el) => ({
            id: el.id,
            subject: el.subject,
            type: el._links.type.title,
            status: el._links.status.title,
            assignee: el._links.assignee?.title ?? '',
            parentId: el._links.parent?.href ? Number(el._links.parent.href.split('/').pop()) : null,
            children: [],
          })));
        },
        error: (err:HttpErrorResponse) => {
          this.results.set([]);
          this.total.set(0);
          this.error.set((err.error as { message?:string }|null)?.message ?? 'Query failed');
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
    const item = buildSavePayload(
      { name, mode: this.mode(), project_id: this.acrossProjects() ? null : this.projectId, tree: this.tree() },
      this.currentId() != null ? this.lastLoaded : null,
    );
    this.saving.set(true);
    const token = this.loadToken;
    const id = this.currentId();
    const req = id != null ? this.service.update(id, item) : this.service.create(item);
    req.pipe(finalize(() => { this.saving.set(false); })).subscribe({
      next: (saved) => {
        const next = applySaved(
          { currentId: this.currentId(), lastLoaded: this.lastLoaded, loadToken: this.loadToken, name: this.name() }, token, saved,
        );
        this.name.set(next.name);
        const wasNew = this.currentId() == null;
        this.currentId.set(next.currentId);
        if (wasNew && next.currentId != null) {
          window.history.replaceState(null, '', `${this.editorPath}?id=${next.currentId}`);
        }
        this.lastLoaded = next.lastLoaded;
        this.service.list().subscribe((res) => { this.saved = res.items; });
      },
      error: (err:HttpErrorResponse) => { this.error.set((err.error as { message?:string }|null)?.message ?? 'Save failed'); },
    });
  }

  load(item:WorkItemQueryItem):void {
    this.loadToken += 1;
    this.lastLoaded = item;
    this.currentId.set(item.id ?? null);
    this.name.set(item.name);
    this.mode.set(item.mode);
    this.acrossProjects.set(item.project_id == null);
    this.tree.set(structuredClone(item.tree));
    this.selected.set(new Set());
  }

  revert():void { if (this.lastLoaded) { this.load(this.lastLoaded); } }
}
