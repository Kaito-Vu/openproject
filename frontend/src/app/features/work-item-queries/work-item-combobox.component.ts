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
  Component, computed, DestroyRef, DOCUMENT, ElementRef, inject, input, output, signal, viewChild,
} from '@angular/core';
import { CheckIconComponent, TriangleDownIconComponent } from '@openproject/octicons-angular';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { Option } from './work-item-filter-schema';
import { filterOptions } from './work-item-multi-select';
import {
  exactMatch, highlightParts, initialActive, moveActive,
} from './work-item-combobox';
import {
  claimPopover, closeOnViewportChange, popoverPosition, PopoverPosition, releasePopover,
} from './work-item-popover';

let nextId = 0;

// Type-ahead single select (the field picker), following the APG combobox with list autocomplete:
// the list opens on typing, click, ArrowDown or Alt+ArrowDown (not on Tab focus), arrows move the
// active option, Enter picks it, Escape closes. Tab commits the typed text only when it exactly
// matches an option label, otherwise the current value stays. The list is position: fixed so the
// scrolling filter card cannot clip it; it closes when anything scrolls. Signals: the app is zoneless.
@Component({
  selector: 'op-work-item-combobox',
  standalone: true,
  imports: [CheckIconComponent, TriangleDownIconComponent],
  styleUrls: ['./work-item-queries.shared.css', './work-item-combobox.component.css'],
  template: `
    <div class="wrap">
      <input
        #box
        class="FormControl-input FormControl-medium"
        type="text"
        role="combobox"
        autocomplete="off"
        spellcheck="false"
        aria-autocomplete="list"
        [attr.aria-expanded]="open()"
        [attr.aria-controls]="listId"
        [attr.aria-activedescendant]="activeId()"
        [attr.aria-label]="label()"
        [placeholder]="placeholder()"
        [value]="inputText()"
        (click)="openList()"
        (input)="onInput($any($event.target).value)"
        (keydown)="onKey($event)"
        (blur)="close()"
      />
      <svg triangle-down-icon size="small" class="caret" aria-hidden="true"></svg>
    </div>

    @if (open()) {
      <div class="pop" [style.left.px]="pos().left" [style.top.px]="pos().top" [style.bottom.px]="pos().bottom"
           [style.width.px]="pos().width" [style.max-height.px]="pos().maxHeight" (mousedown)="$event.preventDefault()">
        <ul role="listbox" [id]="listId" [attr.aria-label]="label()">
          @for (o of shown(); track o.id; let i = $index) {
            <li
              role="option"
              [id]="listId + '-' + i"
              [class.is-active]="i === active()"
              [class.is-current]="o.id === value()"
              [attr.aria-selected]="i === active()"
              (mousedown)="select(o)"
              (mousemove)="active.set(i)"
            >
              @let p = parts(o.name);
              <span>{{ p.before }}<mark>{{ p.match }}</mark>{{ p.after }}</span>
              @if (o.id === value()) {
                <svg check-icon size="small" class="current" aria-hidden="true"></svg>
                <span class="sr-only">{{ text.current }}</span>
              }
            </li>
          }
        </ul>
        @if (shown().length === 0) { <p class="none">{{ text.noMatch }}</p> }
      </div>
    }
  `,
})
export class WorkItemComboboxComponent {
  readonly options = input.required<Option[]>();

  // Selected option id; may not be among the options (unknown saved field): it is then shown as is.
  readonly value = input<string>('');

  readonly label = input.required<string>();

  readonly placeholder = input('');

  readonly changed = output<string>();

  private host = inject<ElementRef<HTMLElement>>(ElementRef);

  private document = inject(DOCUMENT);

  private box = viewChild.required<ElementRef<HTMLInputElement>>('box');

  private I18n = inject(I18nService);

  readonly text = {
    noMatch: this.I18n.t('js.work_item_queries.combobox.no_matching_field'),
    current: this.I18n.t('js.work_item_queries.combobox.current'),
  };

  readonly listId = `wiq-cb-${(nextId += 1)}`;

  readonly open = signal(false);

  // What the user typed while the list is open; null = show the selected option's name.
  readonly typed = signal<string|null>(null);

  readonly active = signal(0);

  readonly pos = signal<PopoverPosition>({
    left: 0, width: 260, top: 0, bottom: null, maxHeight: 280,
  });

  readonly displayText = computed(() => this.options().find((o) => o.id === this.value())?.name ?? this.value());

  readonly inputText = computed(() => this.typed() ?? this.displayText());

  readonly shown = computed(() => filterOptions(this.options(), this.typed() ?? ''));

  // Only reference an option that exists (no dangling id when nothing matches).
  readonly activeId = computed(() => {
    const i = this.active();
    return this.open() && i >= 0 && i < this.shown().length ? `${this.listId}-${i}` : null;
  });

  constructor() {
    closeOnViewportChange(
      this.document,
      inject(DestroyRef),
      () => (this.open() ? this.host.nativeElement.querySelector('.pop') : null),
      () => this.close(),
    );
  }

  parts(name:string) { return highlightParts(name, this.typed() ?? ''); }

  openList():void {
    if (this.open()) { return; }
    const win = this.document.defaultView;
    this.pos.set(popoverPosition(
      this.box().nativeElement.getBoundingClientRect(),
      { width: win?.innerWidth ?? 1024, height: win?.innerHeight ?? 768 },
      280,
    ));
    this.active.set(initialActive(this.shown().map((o) => o.id), this.value()));
    claimPopover(this);
    this.open.set(true);
    this.scrollToActive();
  }

  close():void {
    releasePopover(this);
    this.open.set(false);
    this.typed.set(null);
  }

  onInput(text:string):void {
    this.openList();
    this.typed.set(text);
    this.active.set(0);
  }

  onKey(event:KeyboardEvent):void {
    const n = this.shown().length;
    switch (event.key) {
      case 'ArrowDown':
      case 'ArrowUp':
        event.preventDefault();
        if (!this.open()) { this.openList(); return; }
        if (event.altKey) { return; }
        this.active.set(moveActive(this.active(), event.key === 'ArrowDown' ? 1 : -1, n));
        this.scrollToActive();
        break;
      case 'Enter': {
        if (!this.open()) { return; }
        event.preventDefault();
        const option = this.shown()[this.active()];
        if (option) { this.select(option); }
        break;
      }
      case 'Escape':
        if (this.open()) {
          event.preventDefault();
          event.stopPropagation();
          this.close();
        }
        break;
      case 'Tab': {
        const typed = this.typed();
        const match = typed == null ? null : exactMatch(this.options(), typed);
        if (match) { this.select(match); } else { this.close(); }
        break;
      }
      default:
    }
  }

  select(option:Option):void {
    if (option.id !== this.value()) { this.changed.emit(option.id); }
    this.close();
  }

  private scrollToActive():void {
    setTimeout(() => {
      this.host.nativeElement.querySelector(`#${this.listId}-${this.active()}`)?.scrollIntoView({ block: 'nearest' });
    });
  }
}
