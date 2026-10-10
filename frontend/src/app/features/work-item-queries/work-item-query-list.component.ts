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
import {
  Component, computed, DOCUMENT, ElementRef, Input, OnInit, inject, signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  ChevronDownIconComponent, ListUnorderedIconComponent, PlusIconComponent, SearchIconComponent, StarFillIconComponent,
  StarIconComponent, TrashIconComponent, WorkflowIconComponent,
} from '@openproject/octicons-angular';
import { populateInputsFromDataset } from 'core-app/shared/components/dataset-inputs';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { TimezoneService } from 'core-app/core/datetime/timezone.service';
import { errorText, WorkItemQuery, WorkItemQueryService } from './work-item-query.service';
import { groupAndFilter, initials, isOwnedBy } from './work-item-query-list';

@Component({
  selector: 'op-work-item-query-list',
  standalone: true,
  imports: [
    FormsModule, ChevronDownIconComponent, ListUnorderedIconComponent, PlusIconComponent, SearchIconComponent,
    StarFillIconComponent, StarIconComponent, TrashIconComponent, WorkflowIconComponent,
  ],
  templateUrl: './work-item-query-list.component.html',
  styleUrls: ['./work-item-queries.shared.css', './work-item-query-list.component.css'],
})
export class WorkItemQueryListComponent implements OnInit {
  @Input() currentUserId:number|null = null;

  // UI path of the editor, built by Rails (includes the relative URL root).
  @Input() editorUrl = '';

  readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);

  private service = inject(WorkItemQueryService);

  private I18n = inject(I18nService);

  private timezone = inject(TimezoneService);

  private document = inject(DOCUMENT);

  readonly text = {
    title: this.I18n.t('js.work_item_queries.title'),
    newQuery: this.I18n.t('js.work_item_queries.new_query'),
    favorites: this.I18n.t('js.label_favorites'),
    all: this.I18n.t('js.label_all_uppercase'),
    delete: this.I18n.t('js.button_delete'),
    createFirst: this.I18n.t('js.work_item_queries.list.create_first'),
    emptyFavoritesText: this.I18n.t('js.work_item_queries.list.empty_favorites_text'),
    emptyFavoritesTitle: this.I18n.t('js.work_item_queries.list.empty_favorites_title'),
    emptyNoneText: this.I18n.t('js.work_item_queries.list.empty_none_text'),
    emptyNoneTitle: this.I18n.t('js.work_item_queries.list.empty_none_title'),
    emptyText: this.I18n.t('js.work_item_queries.list.empty_text'),
    emptyTitle: this.I18n.t('js.work_item_queries.list.empty_title'),
    filterPlaceholder: this.I18n.t('js.work_item_queries.list.filter_placeholder'),
    lastModifiedBy: this.I18n.t('js.work_item_queries.list.last_modified_by'),
    loading: this.I18n.t('js.work_item_queries.list.loading'),
    myQueries: this.I18n.t('js.work_item_queries.list.my_queries'),
    noMatchesText: this.I18n.t('js.work_item_queries.list.no_matches_text'),
    noMatchesTitle: this.I18n.t('js.work_item_queries.list.no_matches_title'),
    shared: this.I18n.t('js.work_item_queries.list.shared'),
    sharedQueries: this.I18n.t('js.work_item_queries.list.shared_queries'),
    show: this.I18n.t('js.work_item_queries.list.show'),
    subtitle: this.I18n.t('js.work_item_queries.list.subtitle'),
    titleColumn: this.I18n.t('js.work_item_queries.list.title_column'),
    addFavorite: (name:string) => this.I18n.t('js.work_item_queries.list.add_favorite', { name }),
    removeFavorite: (name:string) => this.I18n.t('js.work_item_queries.list.remove_favorite', { name }),
    deleteNamed: (name:string) => this.I18n.t('js.work_item_queries.list.delete_named', { name }),
    updated: (date:string) => this.I18n.t('js.work_item_queries.list.updated', { date }),
  };

  // Signals: the app is zoneless, so state changed in HTTP callbacks must notify the view itself.
  readonly items = signal<WorkItemQuery[]>([]);

  readonly tab = signal<'favorites'|'all'>('all');

  readonly keyword = signal('');

  readonly collapsed = signal<Record<'my'|'shared', boolean>>({ my: false, shared: false });

  readonly loading = signal(false);

  readonly error = signal<string|null>(null);

  // Ids with a favorite or delete request in flight: their buttons are disabled meanwhile.
  readonly pending = signal(new Set<number>());

  readonly view = computed(() => groupAndFilter(this.items(), {
    tab: this.tab(), keyword: this.keyword(), currentUserId: Number(this.currentUserId),
  }));

  readonly sections = computed(() => {
    const v = this.view();
    return [
      { key: 'my' as const, label: this.text.myQueries, rows: v.my },
      { key: 'shared' as const, label: this.text.sharedQueries, rows: v.shared },
    ];
  });

  readonly initials = initials;

  constructor() {
    populateInputsFromDataset(this);
  }

  ngOnInit():void {
    this.loading.set(true);
    this.service.list().subscribe({
      next: (items) => { this.items.set(items); this.loading.set(false); },
      error: (err:HttpErrorResponse) => {
        this.error.set(errorText(err, this.I18n.t('js.work_item_queries.errors.list_failed')));
        this.loading.set(false);
      },
    });
  }

  toggleSection(section:'my'|'shared'):void {
    this.collapsed.update((c) => ({ ...c, [section]: !c[section] }));
  }

  toggleFavorite(item:WorkItemQuery):void {
    if (this.isPending(item)) { return; }
    const on = !item.favorite;
    this.setFavoriteLocally(item.id, on);
    this.error.set(null);
    this.setPending(item.id, true);
    this.service.setFavorite(item.id, on).subscribe({
      next: () => { this.setPending(item.id, false); },
      error: (err:HttpErrorResponse) => {
        this.setPending(item.id, false);
        this.setFavoriteLocally(item.id, !on);
        this.error.set(errorText(err, this.I18n.t('js.work_item_queries.errors.favorite_failed')));
      },
    });
  }

  remove(item:WorkItemQuery):void {
    if (!this.isOwn(item) || this.isPending(item)) { return; }
    // ponytail: native confirm(); the styled ConfirmDialogService is the upgrade.
    if (!this.document.defaultView?.confirm(this.I18n.t('js.work_item_queries.list.confirm_delete', { name: item.name }))) { return; }
    this.error.set(null);
    this.setPending(item.id, true);
    this.service.remove(item.id).subscribe({
      next: () => {
        this.setPending(item.id, false);
        this.items.update((all) => all.filter((i) => i.id !== item.id));
        // The focused delete button is gone: continue from the list heading.
        setTimeout(() => { this.elementRef.nativeElement.querySelector<HTMLElement>('h1')?.focus(); });
      },
      error: (err:HttpErrorResponse) => {
        this.setPending(item.id, false);
        this.error.set(errorText(err, this.I18n.t('js.work_item_queries.errors.delete_failed')));
      },
    });
  }

  href(item:WorkItemQuery):string { return `${this.editorUrl}?id=${item.id}`; }

  updatedBy(item:WorkItemQuery):string { return item._links.updatedBy.title ?? ''; }

  // Date part in the user's timezone and date format.
  updatedOn(item:WorkItemQuery):string { return this.text.updated(this.timezone.formattedDatetimeComponents(item.updatedAt)[0]); }

  // Stable colour per person for the initials avatar (dark enough for white text: WCAG AA).
  avatarColor(name:string):string {
    const hue = [...name].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 360, 7);
    return `hsl(${hue} 45% 30%)`;
  }

  isOwn(item:WorkItemQuery):boolean { return isOwnedBy(item, Number(this.currentUserId)); }

  isPending(item:WorkItemQuery):boolean { return this.pending().has(item.id); }

  private setPending(id:number, on:boolean):void {
    this.pending.update((prev) => {
      const next = new Set(prev);
      if (on) { next.add(id); } else { next.delete(id); }
      return next;
    });
  }

  private setFavoriteLocally(id:number, favorite:boolean):void {
    this.items.update((all) => all.map((i) => (i.id === id ? { ...i, favorite } : i)));
  }
}
