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
  Component, computed, DestroyRef, DOCUMENT, ElementRef, HostListener, inject, input, output, signal, viewChild,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TriangleDownIconComponent, XIconComponent } from '@openproject/octicons-angular';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { Option } from './work-item-filter-schema';
import { filterOptions, selectedChips, toggleValue } from './work-item-multi-select';
import {
  claimPopover, closeOnViewportChange, popoverPosition, PopoverPosition, releasePopover,
} from './work-item-popover';

let nextId = 0;

// Chips plus a disclosure button that opens a non-modal dialog with a search box and native
// checkboxes (instead of a <select multiple>). The chips' remove buttons sit outside the trigger,
// so they are ordinary tab stops. The dialog is position: fixed so the scrolling filter card cannot
// clip it; it closes when anything scrolls, focus leaves it, or on Escape. Signals: zoneless app.
@Component({
  selector: 'op-work-item-multi-select',
  standalone: true,
  imports: [FormsModule, TriangleDownIconComponent, XIconComponent],
  styleUrls: ['./work-item-queries.shared.css', './work-item-multi-select.component.css'],
  host: { '(focusout)': 'onFocusOut($event)', '(keydown.escape)': 'onEscape($event)' },
  template: `
    <div class="ms" [class.is-open]="open()" [class.is-invalid]="invalid()">
      @for (chip of chips(); track chip.id) {
        <span class="chip">
          {{ chip.name }}
          <button type="button" class="chip-x" [attr.aria-label]="text.remove(chip.name)" (click)="remove(chip.id)">
            <svg x-icon size="xsmall" aria-hidden="true"></svg>
          </button>
        </span>
      }
      <button
        #trigger
        type="button"
        class="trigger"
        aria-haspopup="dialog"
        [attr.aria-expanded]="open()"
        [attr.aria-controls]="open() ? popId : null"
        [attr.aria-invalid]="invalid() || null"
        [attr.aria-describedby]="describedBy()"
        (click)="toggle()"
      >
        <span class="sr-only">{{ label() }}:</span>
        @if (chips().length === 0) {
          <span class="placeholder">{{ placeholder() }}</span>
        } @else {
          <span class="sr-only">{{ text.selected(chips().length) }}</span>
        }
        <svg triangle-down-icon size="small" class="caret" aria-hidden="true"></svg>
      </button>
    </div>

    @if (open()) {
      <div class="pop" role="dialog" [id]="popId" [attr.aria-label]="label()"
           [style.left.px]="pos().left" [style.top.px]="pos().top" [style.bottom.px]="pos().bottom"
           [style.width.px]="pos().width" [style.max-height.px]="pos().maxHeight">
        <div class="pop-search">
          <input type="search" class="FormControl-input FormControl-small" [placeholder]="text.search"
                 [attr.aria-label]="text.searchIn(label())" [ngModel]="query()" (ngModelChange)="query.set($event)" />
        </div>
        <fieldset class="pop-list" (mousedown)="$event.preventDefault()">
          <legend class="sr-only">{{ label() }}</legend>
          @for (o of shown(); track o.id) {
            <label class="pop-item">
              <input type="checkbox" [checked]="isOn(o.id)" (change)="set(o.id, $any($event.target).checked)" />
              <span>{{ o.name }}</span>
            </label>
          }
          @if (shown().length === 0) { <p class="none">{{ text.noMatches }}</p> }
        </fieldset>
        <div class="pop-foot">
          <span>{{ text.selected(selected().length) }}</span>
          <button type="button" class="Button Button--invisible Button--small" [disabled]="selected().length === 0" (click)="clear()">
            <span class="Button-content"><span class="Button-label">{{ text.clear }}</span></span>
          </button>
        </div>
      </div>
    }
  `,
})
export class WorkItemMultiSelectComponent {
  readonly popId = `wiq-ms-${(nextId += 1)}`;

  readonly options = input.required<Option[]>();

  readonly selected = input.required<string[]>();

  readonly label = input.required<string>();

  // Validation state from the condition row (a clause that still needs values).
  readonly invalid = input(false);

  readonly describedBy = input<string|null>(null);

  private I18n = inject(I18nService);

  readonly text = {
    clear: this.I18n.t('js.button_clear'),
    noMatches: this.I18n.t('js.work_item_queries.multi_select.no_matches'),
    search: this.I18n.t('js.work_item_queries.multi_select.search'),
    remove: (name:string) => this.I18n.t('js.work_item_queries.multi_select.remove', { name }),
    searchIn: (label:string) => this.I18n.t('js.work_item_queries.multi_select.search_in', { label }),
    selected: (count:number) => this.I18n.t('js.work_item_queries.multi_select.selected', { count }),
  };

  readonly placeholder = input(this.I18n.t('js.work_item_queries.multi_select.placeholder'));

  readonly changed = output<string[]>();

  private host = inject<ElementRef<HTMLElement>>(ElementRef);

  private document = inject(DOCUMENT);

  private trigger = viewChild.required<ElementRef<HTMLButtonElement>>('trigger');

  readonly open = signal(false);

  readonly query = signal('');

  readonly pos = signal<PopoverPosition>({
    left: 0, width: 260, top: 0, bottom: null, maxHeight: 300,
  });

  readonly chips = computed(() => selectedChips(this.options(), this.selected()));

  readonly shown = computed(() => filterOptions(this.options(), this.query()));

  constructor() {
    closeOnViewportChange(
      this.document,
      inject(DestroyRef),
      () => (this.open() ? this.host.nativeElement.querySelector('.pop') : null),
      () => this.close(),
    );
  }

  isOn(id:string):boolean { return this.selected().includes(id); }

  toggle():void {
    if (this.open()) { this.close(true); return; }
    this.reposition();
    this.query.set('');
    claimPopover(this);
    this.open.set(true);
    setTimeout(() => { this.host.nativeElement.querySelector<HTMLInputElement>('.pop-search input')?.focus(); });
  }

  // Closing returns focus to the trigger only when the user closed it (Escape, trigger), not when
  // focus or a click moved elsewhere or the page scrolled.
  close(refocus = false):void {
    releasePopover(this);
    if (!this.open()) { return; }
    this.open.set(false);
    if (refocus) { this.trigger().nativeElement.focus(); }
  }

  set(id:string, on:boolean):void {
    this.changed.emit(toggleValue(this.selected(), id, on));
    this.repositionSoon(); // chips may wrap onto another line
  }

  remove(id:string):void {
    this.changed.emit(toggleValue(this.selected(), id, false));
    this.trigger().nativeElement.focus(); // the removed chip's button disappears
    this.repositionSoon();
  }

  clear():void {
    this.changed.emit([]);
    this.repositionSoon();
  }

  onEscape(event:Event):void {
    if (!this.open()) { return; }
    event.stopPropagation();
    this.close(true);
  }

  onFocusOut(event:FocusEvent):void {
    const next = event.relatedTarget as Node|null;
    if (this.open() && next && !this.host.nativeElement.contains(next)) { this.close(false); }
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event:Event):void {
    if (this.open() && !this.host.nativeElement.contains(event.target as Node)) { this.close(false); }
  }

  private reposition():void {
    const box = this.host.nativeElement.querySelector('.ms');
    const win = this.document.defaultView;
    if (box) {
      this.pos.set(popoverPosition(box.getBoundingClientRect(), { width: win?.innerWidth ?? 1024, height: win?.innerHeight ?? 768 }));
    }
  }

  private repositionSoon():void { setTimeout(() => { if (this.open()) { this.reposition(); } }); }
}
