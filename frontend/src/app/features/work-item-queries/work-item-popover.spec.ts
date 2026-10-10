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
  claimPopover, openPopover, popoverPosition, releasePopover,
} from './work-item-popover';

describe('popoverPosition', () => {
  const rect = { left: 10, top: 500, bottom: 532, width: 120 };

  it('places the popover below the trigger when there is room', () => {
    expect(popoverPosition(rect, { width: 1200, height: 1000 })).toEqual({
      left: 10, width: 260, top: 536, bottom: null, maxHeight: 300,
    });
  });

  it('flips above, anchored by bottom so a short list stays next to the trigger', () => {
    const pos = popoverPosition(rect, { width: 1200, height: 600 });
    expect(pos.top).toBeNull();
    expect(pos.bottom).toBe(104); // 600 - 500 + 4
  });

  it('stays below when there is no room above either', () => {
    expect(popoverPosition({ ...rect, top: 40, bottom: 72 }, { width: 1200, height: 300 }).top).toBe(76);
  });

  it('clamps left (and width) to the viewport', () => {
    expect(popoverPosition({ ...rect, left: 1100 }, { width: 1200, height: 1000 }).left).toBe(1200 - 260 - 8);
    expect(popoverPosition({ ...rect, left: 0 }, { width: 200, height: 1000 })).toMatchObject({ left: 8, width: 184 });
  });
});

describe('claimPopover', () => {
  it('closes the previously open popover', () => {
    const a = { close: vi.fn() };
    const b = { close: vi.fn() };
    claimPopover(a);
    claimPopover(b);
    expect(a.close).toHaveBeenCalledTimes(1);
    releasePopover(b);
    claimPopover(a);
    expect(b.close).not.toHaveBeenCalled();
    releasePopover(a);
  });
});

describe('openPopover', () => {
  it('closes on a scroll outside the popover, not inside it, and stops listening once released', () => {
    const pop = document.createElement('div');
    const inner = document.createElement('ul');
    pop.appendChild(inner);
    const outside = document.createElement('div');
    document.body.append(pop, outside);
    const close = vi.fn();
    const release = openPopover({ close }, document, () => pop, close);

    inner.dispatchEvent(new Event('scroll'));
    expect(close).not.toHaveBeenCalled();
    outside.dispatchEvent(new Event('scroll'));
    expect(close).toHaveBeenCalledTimes(1);

    release();
    outside.dispatchEvent(new Event('scroll'));
    window.dispatchEvent(new Event('resize'));
    expect(close).toHaveBeenCalledTimes(1);
    pop.remove();
    outside.remove();
  });

  it('releases the single-open registry so a later popover does not close a released one', () => {
    const a = { close: vi.fn() };
    const release = openPopover(a, document, () => null, a.close);
    release(); // e.g. the owner was destroyed while open
    const b = { close: vi.fn() };
    openPopover(b, document, () => null, b.close)();
    expect(a.close).not.toHaveBeenCalled();
  });
});
