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

// Next active index when moving through a list of n options; wraps at both ends.
export function moveActive(index:number, delta:number, n:number):number {
  return n === 0 ? -1 : (((index + delta) % n) + n) % n;
}

// Index to highlight when the list opens: the selected option if it is shown, else the first one.
export function initialActive(ids:string[], selected:string):number {
  const i = ids.indexOf(selected);
  return i >= 0 ? i : 0;
}

// Splits a label around the first case-insensitive match of the typed text, to bold the match.
export function highlightParts(label:string, query:string):{ before:string; match:string; after:string } {
  const q = query.trim();
  const at = q ? label.toLowerCase().indexOf(q.toLowerCase()) : -1;
  if (at < 0) { return { before: label, match: '', after: '' }; }
  return { before: label.slice(0, at), match: label.slice(at, at + q.length), after: label.slice(at + q.length) };
}

// The option whose label equals the typed text (ignoring case and outer blanks), if any. Tab commits
// only such an exact match; anything else keeps the current value.
export function exactMatch<T extends { name:string }>(options:T[], typed:string):T|null {
  const q = typed.trim().toLowerCase();
  return q ? options.find((o) => o.name.toLowerCase() === q) ?? null : null;
}
