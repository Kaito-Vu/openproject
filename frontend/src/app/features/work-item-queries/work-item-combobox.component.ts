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
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { Option } from './work-item-filter-schema';
import { filterOptions, popoverPosition } from './work-item-multi-select';
import { highlightParts, initialActive, moveActive } from './work-item-combobox';

let nextId = 0;

// Type-ahead single select (replaces the plain <select> for the field picker): the input shows the
// chosen option, typing filters the list, arrows + Enter pick. The list is position: fixed so the
// scrolling filter card cannot clip it. Signals: the app runs zoneless.
@Component({
  selector: 'op-work-item-combobox',
  standalone: true,
  styleUrls: ['./work-item-queries.shared.css', './work-item-combobox.component.css'],
  template: `
    <div class="wrap">
      <input
        #box
        class="wiq-control"
        type="text"
        role="combobox"
        autocomplete="off"
        spellcheck="false"
        aria-autocomplete="list"
        [attr.aria-expanded]="open()"
        [attr.aria-controls]="listId"
        [attr.aria-activedescendant]="open() && active() >= 0 ? listId + '-' + active() : null"
        [attr.aria-label]="label()"
        [placeholder]="placeholder()"
        [value]="text()"
        (focus)="openList(box)"
        (click)="openList(box)"
        (input)="onInput($any($event.target).value)"
        (keydown)="onKey($event, box)"
        (blur)="close()"
      />
      <svg class="caret" width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 6l4 4 4-4"/></svg>
    </div>

    @if (open()) {
      <ul class="pop" role="listbox" [id]="listId" [style.left.px]="pos().left" [style.top.px]="pos().top" [style.width.px]="pos().width">
        @for (o of shown(); track o.id; let i = $index) {
          <li
            role="option"
            [id]="listId + '-' + i"
            [class.is-active]="i === active()"
            [class.is-selected]="o.id === value()"
            [attr.aria-selected]="o.id === value()"
            (mousedown)="pick(o, $event)"
            (mousemove)="active.set(i)"
          >
            @let p = parts(o.name);
            {{ p.before }}<mark>{{ p.match }}</mark>{{ p.after }}
          </li>
        } @empty {
          <li class="none">{{ noMatchText }}</li>
        }
      </ul>
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

  readonly noMatchText = inject(I18nService).t('js.work_item_queries.combobox.no_matching_field');

  readonly listId = `wiq-cb-${(nextId += 1)}`;

  readonly open = signal(false);

  // What the user typed while the list is open; null = show the selected option's name.
  readonly typed = signal<string|null>(null);

  readonly active = signal(0);

  readonly pos = signal({ left: 0, top: 0, width: 260 });

  readonly displayText = computed(() => this.options().find((o) => o.id === this.value())?.name ?? this.value());

  readonly text = computed(() => this.typed() ?? this.displayText());

  readonly shown = computed(() => filterOptions(this.options(), this.typed() ?? ''));

  parts(name:string) { return highlightParts(name, this.typed() ?? ''); }

  openList(input:HTMLInputElement):void {
    if (this.open()) { return; }
    this.pos.set(popoverPosition(input.getBoundingClientRect(), window.innerHeight, 280));
    this.typed.set(null);
    this.active.set(initialActive(this.shown().map((o) => o.id), this.value()));
    this.open.set(true);
    input.select();
    this.scrollToActive();
  }

  close():void {
    this.open.set(false);
    this.typed.set(null);
  }

  onInput(text:string):void {
    this.typed.set(text);
    this.active.set(0);
    this.open.set(true);
  }

  onKey(event:KeyboardEvent, input:HTMLInputElement):void {
    const n = this.shown().length;
    switch (event.key) {
      case 'ArrowDown':
      case 'ArrowUp':
        event.preventDefault();
        if (!this.open()) { this.openList(input); return; }
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
        if (this.open()) { event.preventDefault(); this.close(); }
        break;
      case 'Tab':
        this.close();
        break;
      default:
    }
  }

  pick(option:Option, event:MouseEvent):void {
    event.preventDefault(); // keep focus in the input
    this.select(option);
  }

  private select(option:Option):void {
    if (option.id !== this.value()) { this.changed.emit(option.id); }
    this.close();
  }

  private scrollToActive():void {
    setTimeout(() => {
      this.host.nativeElement.querySelector(`#${this.listId}-${this.active()}`)?.scrollIntoView({ block: 'nearest' });
    });
  }

  @HostListener('window:resize')
  @HostListener('window:scroll')
  onViewportChange():void { if (this.open()) { this.close(); } }
}
