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

export interface PopoverPosition { left:number; width:number; top:number|null; bottom:number|null; maxHeight:number }

// Where to place a fixed popover at its trigger: below by default, above when there is no room below
// (anchored by `bottom`, so a short list sits right above the trigger), left clamped to the viewport.
export function popoverPosition(
  rect:{ left:number; bottom:number; top:number; width:number },
  viewport:{ width:number; height:number },
  height = 300,
  minWidth = 260,
):PopoverPosition {
  const width = Math.min(Math.max(rect.width, minWidth), viewport.width - 16);
  const left = Math.max(8, Math.min(rect.left, viewport.width - width - 8));
  const below = viewport.height - rect.bottom >= height || rect.top < height;
  return below
    ? { left, width, top: rect.bottom + 4, bottom: null, maxHeight: height }
    : { left, width, top: null, bottom: viewport.height - rect.top + 4, maxHeight: height };
}

// Only one popover is open at a time: opening one closes the previous one.
interface Closable { close():void }
let current:Closable|null = null;

export function claimPopover(owner:Closable):void {
  if (current && current !== owner) { current.close(); }
  current = owner;
}

export function releasePopover(owner:Closable):void {
  if (current === owner) { current = null; }
}

// Marks `owner` as the open popover (closing any other) and, while it is open, closes it when any
// ancestor scrolls (OpenProject scrolls #content-wrapper, not the window; scroll does not bubble,
// hence the capture phase) or the window resizes: fixed popovers do not follow their trigger.
// Scrolling inside the popover itself (its list) is ignored. Returns the function that undoes all
// of it; call it on close and on destroy.
export function openPopover(
  owner:Closable,
  doc:Document,
  popover:() => Element|null,
  close:() => void,
):() => void {
  claimPopover(owner);
  const win = doc.defaultView;
  const onScroll = (e:Event):void => {
    const pop = popover();
    if (pop && !pop.contains(e.target as Node)) { close(); }
  };
  doc.addEventListener('scroll', onScroll, { capture: true, passive: true });
  win?.addEventListener('resize', close);
  return () => {
    doc.removeEventListener('scroll', onScroll, { capture: true });
    win?.removeEventListener('resize', close);
    releasePopover(owner);
  };
}
