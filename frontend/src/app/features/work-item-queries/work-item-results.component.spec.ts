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

import { nestByParent } from './work-item-results.component';

describe('nestByParent', () => {
  it('nests children under a parent present in the result and keeps orphans as roots', () => {
    const rowsIn = [
      { id: 1, subject: 'a', parentId: null },
      { id: 2, subject: 'b', parentId: 1 },
      { id: 3, subject: 'c', parentId: 99 },
    ] as any[];
    const out = nestByParent(rowsIn);
    expect(out.map((r) => r.id)).toEqual([1, 3]);
    expect(out[0].children.map((r:any) => r.id)).toEqual([2]);
  });
});
