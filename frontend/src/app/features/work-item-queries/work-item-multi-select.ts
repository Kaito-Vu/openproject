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

import { Option } from './work-item-filter-schema';

// Options matching the search text (case-insensitive, on the label), in their original order.
export function filterOptions(options:Option[], search:string):Option[] {
  const q = search.trim().toLowerCase();
  return q ? options.filter((o) => o.name.toLowerCase().includes(q)) : options;
}

// Adds or removes one id, keeping the order in which the user picked the values.
export function toggleValue(selected:string[], id:string, on:boolean):string[] {
  const without = selected.filter((v) => v !== id);
  return on ? [...without, id] : without;
}

// Selected ids with their labels; an id that is not among the options keeps the id as its label.
export function selectedChips(options:Option[], selected:string[]):Option[] {
  const byId = new Map(options.map((o) => [o.id, o.name]));
  return selected.map((id) => ({ id, name: byId.get(id) ?? id }));
}
