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

import { WorkItemQueryItem } from './work-item-query.service';

export interface ListOptions { tab:'favorites'|'all'; keyword:string; currentUserId:number }

export function groupAndFilter(items:WorkItemQueryItem[], opts:ListOptions):{ my:WorkItemQueryItem[]; shared:WorkItemQueryItem[] } {
  const keyword = opts.keyword.trim().toLowerCase();
  const keep = (i:WorkItemQueryItem):boolean => (opts.tab === 'all' || !!i.favorite)
    && (!keyword || i.name.toLowerCase().includes(keyword));
  const byName = (a:WorkItemQueryItem, b:WorkItemQueryItem):number => a.name.localeCompare(b.name);
  const visible = items.filter(keep);

  return {
    my: visible.filter((i) => i.user_id === opts.currentUserId).sort(byName),
    shared: visible.filter((i) => i.user_id !== opts.currentUserId && i.public).sort(byName),
  };
}

export function initials(name:string|undefined):string {
  return (name ?? '').trim().split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
}
