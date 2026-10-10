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
  pruneIncomplete, layout, withKeys, Condition,
  addCondition, canGroup, emptyTree, group, Group, removeAt, rows, setOp, ungroup, updateCondition,
} from './work-item-query-tree';

const c = (field:string) => ({ field, operator: '=', values: ['1'] });
const g = (op:'and'|'or', ...children:any[]):Group => ({ op, children });

describe('work item query tree', () => {
  it('adds a condition to a group without mutating the input', () => {
    const t = emptyTree();
    const next = addCondition(t, []);
    expect(t.children.length).toBe(0);
    expect(next.children.length).toBe(1);
  });

  it('removes a node and prunes groups that become empty', () => {
    const t = g('and', c('a'), g('or', c('b')));
    const next = removeAt(t, [1, 0]);
    expect(next.children.length).toBe(1);
  });

  it('prunes an emptied nested group while keeping its ancestors', () => {
    const t = g('and', c('a'), g('or', c('b'), g('and', c('x'))));
    const next = removeAt(t, [1, 1, 0]);
    expect(next).toEqual(g('and', c('a'), g('or', c('b'))));
  });

  it('sets the op of a group', () => {
    expect(setOp(g('and', c('a')), [], 'or').op).toBe('or');
  });

  it('groups contiguous siblings with the opposite op', () => {
    const t = g('and', c('a'), c('b'), c('c'));
    const next = group(t, [[0], [1]]);
    expect(next.children.length).toBe(2);
    expect((next.children[0] as Group).op).toBe('or');
    expect((next.children[0] as Group).children.length).toBe(2);
  });

  it('groups inside a nested group using the nested parent op', () => {
    const t = g('and', c('z'), g('or', c('a'), c('b'), c('c')));
    const next = group(t, [[1, 1], [1, 2]]);
    const inner = next.children[1] as Group;
    expect(inner.children.length).toBe(2);
    expect((inner.children[1] as Group).op).toBe('and');
    expect((inner.children[1] as Group).children.length).toBe(2);
  });

  it('refuses to group non-contiguous or cross-parent selections', () => {
    expect(canGroup([[0], [2]])).toBe(false);
    expect(canGroup([[0], [1, 0]])).toBe(false);
    expect(canGroup([[0]])).toBe(false);
    expect(canGroup([[0], [1]])).toBe(true);
  });

  it('ungroups a group into its parent', () => {
    const t = g('and', g('or', c('a'), c('b')), c('c'));
    const next = ungroup(t, [0]);
    expect(next.children.length).toBe(3);
  });

  it('returns the tree unchanged when ungrouping the root', () => {
    const t = g('and', c('a'));
    expect(ungroup(t, [])).toBe(t);
  });

  it('updates a condition', () => {
    const next = updateCondition(g('and', c('a')), [0], { field: 'z' });
    expect((next.children[0] as any).field).toBe('z');
  });

  it('lists condition rows with depth and parent op', () => {
    const t = g('and', c('a'), g('or', c('b'), c('d')));
    const r = rows(t);
    expect(r.map((x) => x.depth)).toEqual([0, 1, 1]);
    expect(r[2].parentOp).toBe('or');
    expect(r[2].indexInParent).toBe(1);
  });

  it('returns no rows for an empty tree', () => {
    expect(rows(emptyTree())).toEqual([]);
  });

  it('never mutates its input', () => {
    const make = () => g('and', c('a'), c('b'), g('or', c('d'), c('e')));
    const deepFreeze = (o:any):any => {
      Object.values(o).forEach((v) => typeof v === 'object' && v !== null && deepFreeze(v));
      return Object.freeze(o);
    };
    const t = deepFreeze(make());
    expect(() => {
      addCondition(t, [2]);
      removeAt(t, [2, 0]);
      setOp(t, [2], 'and');
      updateCondition(t, [0], { field: 'q' });
      group(t, [[0], [1]]);
      ungroup(t, [2]);
      rows(t);
    }).not.toThrow();
    expect(t).toEqual(make());
  });

  describe('invalid or stale paths', () => {
    const t = () => g('and', c('a'), g('or', c('b')));

    it('removeAt ignores the root and missing paths', () => {
      const tree = t();
      [[], [9], [9, 0], [0, 0]].forEach((p) => expect(removeAt(tree, p)).toBe(tree));
    });

    it('ungroup ignores missing and non-group paths', () => {
      const tree = t();
      [[9], [9, 0], [0]].forEach((p) => expect(ungroup(tree, p)).toBe(tree));
    });

    it('setOp ignores condition and missing paths', () => {
      const tree = t();
      [[0], [9]].forEach((p) => expect(setOp(tree, p, 'or')).toBe(tree));
    });

    it('updateCondition ignores group and missing paths', () => {
      const tree = t();
      [[1], [9]].forEach((p) => expect(updateCondition(tree, p, { field: 'z' })).toBe(tree));
    });

    it('group ignores out-of-range paths', () => {
      const tree = t();
      expect(group(tree, [[0], [5]])).toBe(tree);
      expect(group(tree, [[8, 0], [8, 1]])).toBe(tree);
    });

    it('addCondition ignores condition and missing parents', () => {
      const tree = t();
      [[0], [9]].forEach((p) => expect(addCondition(tree, p)).toBe(tree));
    });
  });
});

describe('layout', () => {
  it('lists group headers before their children, so every group op is shown on a row at index > 0', () => {
    // A and (B or C): the root "and" sits on the group header row, the "or" on C.
    const t = g('and', c('a'), g('or', c('b'), c('c')));
    const r = layout(t);
    expect(r.map((x) => [x.kind, x.path.join('.'), x.depth, x.indexInParent, x.parentOp])).toEqual([
      ['condition', '0', 0, 0, 'and'],
      ['group', '1', 0, 1, 'and'],
      ['condition', '1.0', 1, 0, 'or'],
      ['condition', '1.1', 1, 1, 'or'],
    ]);
  });

  it('shows an op whose following siblings are all groups (the review case)', () => {
    const t = g('or', g('and', c('a'), c('b')), g('and', c('c'), c('d')));
    const atIndex1 = layout(t).filter((x) => x.indexInParent > 0);
    expect(atIndex1.map((x) => [x.kind, x.parentPath.join('.'), x.parentOp])).toEqual([
      ['condition', '0', 'and'], ['group', '', 'or'], ['condition', '1', 'and'],
    ]);
  });

  it('keys conditions by their client key and groups by path; rows() keeps listing conditions only', () => {
    const t = g('and', { key: 'k1', ...c('a') }, g('or', c('b')));
    expect(layout(t).map((x) => x.key)).toEqual(['k1', 'g1', '1.0']);
    expect(rows(t).map((x) => x.path)).toEqual([[0], [1, 0]]);
  });
});

describe('client keys', () => {
  it('gives new conditions a unique key', () => {
    const t = addCondition(addCondition(emptyTree(), []), []);
    const [a, b] = t.children as Condition[];
    expect(a.key).toBeTruthy();
    expect(a.key).not.toBe(b.key);
  });

  it('withKeys adds keys to loaded conditions without mutating or replacing existing keys', () => {
    const t = g('and', { key: 'keep', ...c('a') }, g('or', c('b')));
    const before = JSON.stringify(t);
    const next = withKeys(t);
    expect(JSON.stringify(t)).toBe(before);
    expect((next.children[0] as Condition).key).toBe('keep');
    expect(((next.children[1] as Group).children[0] as Condition).key).toBeTruthy();
  });

  it('pruneIncomplete strips keys so they never reach the API', () => {
    const t = withKeys(g('and', c('a'), g('or', c('b'))));
    expect(JSON.stringify(pruneIncomplete(t))).not.toContain('key');
    expect(pruneIncomplete(t)).toEqual(g('and', c('a'), g('or', c('b'))));
  });
});

describe('pruneIncomplete', () => {
  const done = (field:string) => ({ field, operator: '=', values: ['1'] });
  const blank = { field: '', operator: '=', values: [] as string[] };

  it('drops conditions without a field and keeps complete ones', () => {
    const t:Group = { op: 'and', children: [blank, done('status')] };
    expect(pruneIncomplete(t).children).toEqual([done('status')]);
  });

  it('drops groups that become empty and keeps the root', () => {
    const t:Group = { op: 'and', children: [{ op: 'or', children: [blank] }] };
    expect(pruneIncomplete(t)).toEqual({ op: 'and', children: [] });
  });

  it('keeps nested groups with complete conditions and does not mutate the input', () => {
    const t:Group = { op: 'and', children: [blank, { op: 'or', children: [done('type'), blank] }] };
    const before = JSON.stringify(t);
    expect(pruneIncomplete(t)).toEqual({ op: 'and', children: [{ op: 'or', children: [done('type')] }] });
    expect(JSON.stringify(t)).toBe(before);
  });
});
