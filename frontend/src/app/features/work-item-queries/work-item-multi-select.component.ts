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

import {
  Component, computed, ElementRef, HostListener, inject, input, output, signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { Option } from './work-item-filter-schema';
import {
  filterOptions, popoverPosition, selectedChips, toggleValue,
} from './work-item-multi-select';

let nextId = 0;

// Chips + searchable checkbox popover instead of the native <select multiple>. The popover is
// position: fixed so the scrolling filter card cannot clip it. Signals: the app runs zoneless.
@Component({
  selector: 'op-work-item-multi-select',
  standalone: true,
  imports: [FormsModule],
  styleUrls: ['./work-item-queries.shared.css', './work-item-multi-select.component.css'],
  template: `
    <div class="box" [class.is-open]="open()" (click)="toggle($event)" (keydown.enter)="toggle($event)" (keydown.space)="toggle($event)"
         role="combobox" tabindex="0" aria-haspopup="dialog" [attr.aria-controls]="popId" [attr.aria-expanded]="open()" [attr.aria-label]="label()">
      @for (chip of chips(); track chip.id) {
        <span class="chip">
          {{ chip.name }}
          <button type="button" class="chip-x" [attr.aria-label]="text.remove(chip.name)" (click)="remove(chip.id, $event)">
            <svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg>
          </button>
        </span>
      } @empty {
        <span class="placeholder">{{ placeholder() }}</span>
      }
      <svg class="caret" width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 6l4 4 4-4"/></svg>
    </div>

    @if (open()) {
      <div class="pop" role="dialog" [id]="popId" [attr.aria-label]="label()" [style.left.px]="pos().left" [style.top.px]="pos().top" [style.width.px]="pos().width">
        <div class="pop-search">
          <input type="search" class="wiq-control" [placeholder]="text.search" [attr.aria-label]="text.searchIn(label())" [ngModel]="query()" (ngModelChange)="query.set($event)" (keydown.escape)="close()" />
        </div>
        <ul class="pop-list" role="listbox" aria-multiselectable="true">
          @for (o of shown(); track o.id) {
            <li role="option" [attr.aria-selected]="isOn(o.id)">
              <label>
                <input type="checkbox" [checked]="isOn(o.id)" (change)="set(o.id, $any($event.target).checked)" />
                <span>{{ o.name }}</span>
              </label>
            </li>
          } @empty {
            <li class="none">{{ text.noMatches }}</li>
          }
        </ul>
        <div class="pop-foot">
          <span>{{ text.selected(selected().length) }}</span>
          <button type="button" class="link" [disabled]="selected().length === 0" (click)="clear()">{{ text.clear }}</button>
        </div>
      </div>
    }
  `,
})
export class WorkItemMultiSelectComponent {
  readonly popId = `wiq-ms-${(nextId += 1)}`;

  readonly options = input.required<Option[]>();

  readonly selected = input.required<string[]>();

  private I18n = inject(I18nService);

  readonly text = {
    clear: this.I18n.t('js.button_clear'),
    noMatches: this.I18n.t('js.work_item_queries.multi_select.no_matches'),
    search: this.I18n.t('js.work_item_queries.multi_select.search'),
    remove: (name:string) => this.I18n.t('js.work_item_queries.multi_select.remove', { name }),
    searchIn: (label:string) => this.I18n.t('js.work_item_queries.multi_select.search_in', { label }),
    selected: (count:number) => this.I18n.t('js.work_item_queries.multi_select.selected', { count }),
  };

  readonly label = input.required<string>();

  readonly placeholder = input(this.I18n.t('js.work_item_queries.multi_select.placeholder'));

  readonly changed = output<string[]>();

  private host = inject<ElementRef<HTMLElement>>(ElementRef);

  readonly open = signal(false);

  readonly query = signal('');

  readonly pos = signal({ left: 0, top: 0, width: 260 });

  readonly chips = computed(() => selectedChips(this.options(), this.selected()));

  readonly shown = computed(() => filterOptions(this.options(), this.query()));

  isOn(id:string):boolean { return this.selected().includes(id); }

  toggle(event:Event):void {
    event.preventDefault();
    if (this.open()) { this.close(); return; }
    const box = this.host.nativeElement.querySelector('.box');
    if (box) { this.pos.set(popoverPosition(box.getBoundingClientRect(), window.innerHeight)); }
    this.query.set('');
    this.open.set(true);
    setTimeout(() => { this.host.nativeElement.querySelector<HTMLInputElement>('.pop-search input')?.focus(); });
  }

  close():void {
    this.open.set(false);
    this.host.nativeElement.querySelector<HTMLElement>('.box')?.focus();
  }

  set(id:string, on:boolean):void { this.changed.emit(toggleValue(this.selected(), id, on)); }

  remove(id:string, event:Event):void {
    event.stopPropagation();
    this.changed.emit(toggleValue(this.selected(), id, false));
  }

  clear():void { this.changed.emit([]); }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event:Event):void {
    if (this.open() && !this.host.nativeElement.contains(event.target as Node)) { this.open.set(false); }
  }

  @HostListener('window:resize')
  @HostListener('window:scroll')
  onViewportChange():void { if (this.open()) { this.open.set(false); } }
}
