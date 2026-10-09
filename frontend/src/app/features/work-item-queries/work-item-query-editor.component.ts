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
import { finalize } from 'rxjs';
import { Component, ElementRef, Input, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';
import {
  addCondition, Condition, emptyTree, group, Group, Path, removeAt, Row, rows, setOp, ungroup, updateCondition,
} from './work-item-query-tree';
import { buildSavePayload, WorkItemQueryItem, WorkItemQueryService } from './work-item-query.service';
import { ResultRow, WorkItemResultsComponent } from './work-item-results.component';
import { WorkItemConditionRowComponent } from './work-item-condition-row.component';

@Component({
  selector: 'op-work-item-query-editor',
  standalone: true,
  imports: [FormsModule, WorkItemResultsComponent, WorkItemConditionRowComponent],
  templateUrl: './work-item-query-editor.component.html',
})
export class WorkItemQueryEditorComponent implements OnInit {
  @Input() projectId:number|null = null;

  @Input() queryId:number|null = null;

  readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);

  private service = inject(WorkItemQueryService);

  tree:Group = emptyTree();

  mode:'flat'|'tree' = 'flat';

  acrossProjects = false;

  results:ResultRow[] = [];

  error:string|null = null;

  saved:WorkItemQueryItem[] = [];

  selected = new Set<string>();

  currentId:number|null = null;

  name = '';

  loading = false;

  total = 0;

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
      error: (err:HttpErrorResponse) => { this.error = (err.error as { message?:string }|null)?.message ?? 'Loading queries failed'; },
    });
  }

  get rows():Row[] { return rows(this.tree); }

  run():void {
    if (this.loading) { return; }
    this.loading = true;
    this.error = null;
    this.service
      .execute({ tree: this.tree, mode: this.mode, project_id: this.acrossProjects ? null : this.projectId, pageSize: 500 })
      .pipe(finalize(() => { this.loading = false; }))
      .subscribe({
        next: (res) => {
          this.total = res._embedded.results.total ?? 0;
          this.results = res._embedded.results._embedded.elements.map((el) => ({
            id: el.id,
            subject: el.subject,
            type: el._links.type.title,
            status: el._links.status.title,
            assignee: el._links.assignee?.title ?? '',
            parentId: el._links.parent?.href ? Number(el._links.parent.href.split('/').pop()) : null,
            children: [],
          }));
        },
        error: (err:HttpErrorResponse) => {
          this.results = [];
          this.total = 0;
          this.error = (err.error as { message?:string }|null)?.message ?? 'Query failed';
        },
      });
  }

  add():void { this.tree = addCondition(this.tree, []); }

  remove(path:Path):void {
    this.tree = removeAt(this.tree, path);
    this.selected.clear();
  }

  update(path:Path, patch:Partial<Condition>):void { this.tree = updateCondition(this.tree, path, patch); }

  toggleSelected(path:Path, checked:boolean):void {
    const key = path.join('.');
    if (checked) { this.selected.add(key); } else { this.selected.delete(key); }
  }

  group():void {
    this.tree = group(this.tree, [...this.selected].map((s) => s.split('.').map(Number)));
    this.selected.clear();
  }

  ungroup(path:Path):void {
    this.tree = ungroup(this.tree, path);
    this.selected.clear();
  }

  toggleOp(row:Row):void { this.tree = setOp(this.tree, row.parentPath, row.parentOp === 'and' ? 'or' : 'and'); }

  save():void {
    const name = this.name || (window.prompt('Query name') ?? '');
    if (!name) { return; }
    this.name = name;
    const item = buildSavePayload(
      { name, mode: this.mode, project_id: this.acrossProjects ? null : this.projectId, tree: this.tree },
      this.currentId != null ? this.lastLoaded : null,
    );
    const req = this.currentId != null ? this.service.update(this.currentId, item) : this.service.create(item);
    req.subscribe({
      next: (saved) => {
        this.currentId = saved.id ?? this.currentId;
        this.lastLoaded = saved;
        this.service.list().subscribe((res) => { this.saved = res.items; });
      },
      error: (err:HttpErrorResponse) => { this.error = (err.error as { message?:string }|null)?.message ?? 'Save failed'; },
    });
  }

  load(item:WorkItemQueryItem):void {
    this.lastLoaded = item;
    this.currentId = item.id ?? null;
    this.name = item.name;
    this.mode = item.mode;
    this.acrossProjects = item.project_id == null;
    this.tree = structuredClone(item.tree);
    this.selected.clear();
  }

  revert():void { if (this.lastLoaded) { this.load(this.lastLoaded); } }
}
