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
import { Component, ElementRef, Input, OnInit, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';
import { WorkItemQueryItem, WorkItemQueryService } from './work-item-query.service';
import { groupAndFilter, initials } from './work-item-query-list';

@Component({
  selector: 'op-work-item-query-list',
  standalone: true,
  imports: [FormsModule, DatePipe],
  templateUrl: './work-item-query-list.component.html',
})
export class WorkItemQueryListComponent implements OnInit {
  @Input() projectId:number|null = null;

  @Input() currentUserId:number|null = null;

  readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);

  private service = inject(WorkItemQueryService);

  // Signals: the app is zoneless, so state changed in HTTP callbacks must notify the view itself.
  readonly items = signal<WorkItemQueryItem[]>([]);

  readonly tab = signal<'favorites'|'all'>('all');

  readonly keyword = signal('');

  readonly collapsed = signal({ my: false, shared: false });

  readonly loading = signal(false);

  readonly error = signal<string|null>(null);

  readonly view = computed(() => groupAndFilter(this.items(), {
    tab: this.tab(), keyword: this.keyword(), currentUserId: Number(this.currentUserId),
  }));

  readonly initials = initials;

  constructor() {
    populateInputsFromDataset(this);
  }

  get editorUrl():string {
    return this.projectId ? `/projects/${this.projectId}/queries/editor` : '/queries/editor';
  }

  ngOnInit():void {
    this.loading.set(true);
    this.service.list().subscribe({
      next: (res) => { this.items.set(res.items); this.loading.set(false); },
      error: (err:HttpErrorResponse) => { this.fail(err, 'Loading queries failed'); this.loading.set(false); },
    });
  }

  toggleSection(section:'my'|'shared'):void {
    this.collapsed.update((c) => ({ ...c, [section]: !c[section] }));
  }

  toggleFavorite(item:WorkItemQueryItem):void {
    const on = !item.favorite;
    this.setFavoriteLocally(item.id, on);
    this.error.set(null);
    this.service.setFavorite(item.id!, on).subscribe({
      error: (err:HttpErrorResponse) => { this.setFavoriteLocally(item.id, !on); this.fail(err, 'Updating favorite failed'); },
    });
  }

  remove(item:WorkItemQueryItem):void {
    if (!this.isOwn(item)) { return; }
    if (!confirm(`Delete query "${item.name}"?`)) { return; }
    this.error.set(null);
    this.service.remove(item.id!).subscribe({
      next: () => { this.items.update((all) => all.filter((i) => i.id !== item.id)); },
      error: (err:HttpErrorResponse) => { this.fail(err, 'Deleting query failed'); },
    });
  }

  open(item:WorkItemQueryItem):void { window.location.href = `${this.editorUrl}?id=${item.id!}`; }

  newQuery():void { window.location.href = this.editorUrl; }

  isOwn(item:WorkItemQueryItem):boolean { return item.user_id === Number(this.currentUserId); }

  private setFavoriteLocally(id:number|undefined, favorite:boolean):void {
    this.items.update((all) => all.map((i) => (i.id === id ? { ...i, favorite } : i)));
  }

  private fail(err:HttpErrorResponse, fallback:string):void {
    this.error.set((err.error as { message?:string }|null)?.message ?? fallback);
  }
}
