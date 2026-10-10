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

import { ComponentFixture, TestBed } from '@angular/core/testing';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { WorkItemComboboxComponent } from './work-item-combobox.component';
import { WorkItemMultiSelectComponent } from './work-item-multi-select.component';

const OPTIONS = [{ id: 'assignee', name: 'Assignee' }, { id: 'status', name: 'Status' }, { id: 'subject', name: 'Subject' }];

const key = (el:Element, k:string, init:KeyboardEventInit = {}) => {
  el.dispatchEvent(new KeyboardEvent('keydown', {
    key: k, bubbles: true, cancelable: true, ...init,
  }));
};

describe('work item popover components', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [{ provide: I18nService, useValue: { t: (k:string, o?:{ count?:number }) => (o?.count != null ? `${o.count} ${k}` : k) } }],
    });
  });

  describe('WorkItemComboboxComponent', () => {
    let fixture:ComponentFixture<WorkItemComboboxComponent>;
    let input:HTMLInputElement;
    let picked:string[];

    beforeEach(() => {
      fixture = TestBed.createComponent(WorkItemComboboxComponent);
      fixture.componentRef.setInput('options', OPTIONS);
      fixture.componentRef.setInput('value', 'status');
      fixture.componentRef.setInput('label', 'Field');
      picked = [];
      fixture.componentInstance.changed.subscribe((v) => picked.push(v));
      document.body.appendChild(fixture.nativeElement);
      fixture.detectChanges();
      input = fixture.nativeElement.querySelector('input');
    });

    afterEach(() => { fixture.nativeElement.remove(); });

    const listbox = () => fixture.nativeElement.querySelector('[role="listbox"]');

    it('does not open on focus, opens on ArrowDown on the current value, Enter picks the active option', () => {
      input.focus();
      fixture.detectChanges();
      expect(listbox()).toBeNull();
      expect(input.getAttribute('aria-controls')).toBeNull();

      key(input, 'ArrowDown');
      fixture.detectChanges();
      expect(input.getAttribute('aria-expanded')).toBe('true');
      expect(input.getAttribute('aria-controls')).toBe(listbox().id);
      expect(input.getAttribute('aria-activedescendant')).toBe(`${fixture.componentInstance.listId}-1`);
      const active = listbox().querySelector('[aria-selected="true"]');
      expect(active.textContent).toContain('Status');

      key(input, 'ArrowDown');
      key(input, 'Enter');
      fixture.detectChanges();
      expect(picked).toEqual(['subject']);
      expect(listbox()).toBeNull();
    });

    it('drops aria-activedescendant when nothing matches and shows the message outside the listbox', () => {
      input.value = 'zzz';
      input.dispatchEvent(new Event('input'));
      fixture.detectChanges();
      expect(input.getAttribute('aria-activedescendant')).toBeNull();
      expect(listbox().children.length).toBe(0);
      expect(fixture.nativeElement.querySelector('.none')).not.toBeNull();
    });

    it('Escape closes without changing the value', () => {
      key(input, 'ArrowDown');
      fixture.detectChanges();
      key(input, 'Escape');
      fixture.detectChanges();
      expect(listbox()).toBeNull();
      expect(picked).toEqual([]);
    });

    it('Tab commits only an exact label match', () => {
      input.value = 'assign';
      input.dispatchEvent(new Event('input'));
      key(input, 'Tab');
      expect(picked).toEqual([]);

      input.value = 'assignee';
      input.dispatchEvent(new Event('input'));
      key(input, 'Tab');
      expect(picked).toEqual(['assignee']);
    });
  });

  describe('WorkItemMultiSelectComponent', () => {
    let fixture:ComponentFixture<WorkItemMultiSelectComponent>;
    let changes:string[][];

    beforeEach(() => {
      fixture = TestBed.createComponent(WorkItemMultiSelectComponent);
      fixture.componentRef.setInput('options', OPTIONS);
      fixture.componentRef.setInput('selected', ['status']);
      fixture.componentRef.setInput('label', 'Values for Field');
      changes = [];
      fixture.componentInstance.changed.subscribe((v) => changes.push(v));
      document.body.appendChild(fixture.nativeElement);
      fixture.detectChanges();
    });

    afterEach(() => { fixture.nativeElement.remove(); });

    const el = () => fixture.nativeElement as HTMLElement;
    const trigger = () => el().querySelector<HTMLButtonElement>('button.trigger')!;
    const dialog = () => el().querySelector('[role="dialog"]');

    it('uses a disclosure button and keeps the chip remove buttons outside it', () => {
      expect(trigger().getAttribute('aria-haspopup')).toBe('dialog');
      expect(trigger().getAttribute('aria-expanded')).toBe('false');
      const remove = el().querySelector<HTMLButtonElement>('.chip-x')!;
      expect(trigger().contains(remove)).toBe(false);
      remove.click();
      expect(changes).toEqual([[]]);
    });

    it('lists plain checkboxes in a fieldset and closes on Escape, returning focus to the trigger', () => {
      trigger().click();
      fixture.detectChanges();
      expect(dialog()).not.toBeNull();
      expect(el().querySelector('fieldset legend')?.textContent).toContain('Values for Field');
      expect(el().querySelector('[role="listbox"], [role="option"]')).toBeNull();
      const boxes = el().querySelectorAll<HTMLInputElement>('fieldset input[type="checkbox"]');
      expect([...boxes].map((b) => b.checked)).toEqual([false, true, false]);

      key(boxes[0], 'Escape');
      fixture.detectChanges();
      expect(dialog()).toBeNull();
      expect(document.activeElement).toBe(trigger());
    });

    it('closes without stealing focus when focus moves outside', () => {
      const outside = document.createElement('button');
      document.body.appendChild(outside);
      trigger().click();
      fixture.detectChanges();
      el().dispatchEvent(new FocusEvent('focusout', { relatedTarget: outside, bubbles: true }));
      fixture.detectChanges();
      expect(dialog()).toBeNull();
      expect(document.activeElement).not.toBe(trigger());
      outside.remove();
    });

    it('closes when an ancestor scrolls, but not when its own list scrolls', () => {
      trigger().click();
      fixture.detectChanges();
      el().querySelector('fieldset')!.dispatchEvent(new Event('scroll'));
      fixture.detectChanges();
      expect(dialog()).not.toBeNull();
      document.body.dispatchEvent(new Event('scroll'));
      fixture.detectChanges();
      expect(dialog()).toBeNull();
    });
  });
});
