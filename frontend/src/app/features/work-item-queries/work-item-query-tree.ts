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

export type Op = 'and'|'or';
// key: client-side identity for rendering (tracking a row across edits); never sent to the API.
export interface Condition { key?:string; field:string; operator:string; values:string[] }
export interface Group { op:Op; children:TreeNode[] }
export type TreeNode = Condition|Group;
export type Path = number[];
export interface Row {
  path:Path; node:Condition; depth:number; parentPath:Path; indexInParent:number; parentOp:Op;
}
export interface GroupRow {
  path:Path; node:Group; depth:number; parentPath:Path; indexInParent:number; parentOp:Op;
}
// One line of the editor: a condition, or the header of a nested group (shown before its children).
export type LayoutRow = ({ kind:'condition'; key:string } & Row)|({ kind:'group'; key:string } & GroupRow);

export const isGroup = (n:TreeNode|undefined):n is Group => !!n && 'children' in n;
export const emptyTree = ():Group => ({ op: 'and', children: [] });

const clone = <T>(v:T):T => structuredClone(v);

let lastKey = 0;
export const newKey = ():string => { lastKey += 1; return `c${lastKey}`; };
const find = (tree:Group, path:Path):TreeNode|undefined => path.reduce<TreeNode|undefined>(
  (n, i) => (isGroup(n) ? n.children[i] : undefined),
  tree,
);
const last = (p:Path) => p[p.length - 1];
const parentOf = (p:Path) => p.slice(0, -1);

function prune(g:Group):Group {
  g.children.forEach((c) => isGroup(c) && prune(c));
  g.children = g.children.filter((c) => !isGroup(c) || c.children.length > 0);
  return g;
}

// Every path-taking function returns the input tree unchanged for an invalid/stale path.
export function addCondition(tree:Group, parent:Path):Group {
  if (!isGroup(find(tree, parent))) { return tree; }
  const next = clone(tree);
  (find(next, parent) as Group).children.push({ key: newKey(), field: '', operator: '=', values: [] });
  return next;
}

export function removeAt(tree:Group, path:Path):Group {
  if (path.length === 0 || !find(tree, path)) { return tree; }
  const next = clone(tree);
  (find(next, parentOf(path)) as Group).children.splice(last(path), 1);
  return prune(next);
}

export function setOp(tree:Group, path:Path, op:Op):Group {
  if (!isGroup(find(tree, path))) { return tree; }
  const next = clone(tree);
  (find(next, path) as Group).op = op;
  return next;
}

export function updateCondition(tree:Group, path:Path, patch:Partial<Condition>):Group {
  const node = find(tree, path);
  if (!node || isGroup(node)) { return tree; }
  const next = clone(tree);
  Object.assign(find(next, path) as Condition, patch);
  return next;
}

export function canGroup(paths:Path[]):boolean {
  if (paths.length < 2) { return false; }
  const parent = parentOf(paths[0]).join('.');
  if (!paths.every((p) => p.length > 0 && parentOf(p).join('.') === parent)) { return false; }
  const idx = paths.map(last).sort((a, b) => a - b);
  return idx.every((v, i) => i === 0 || v === idx[i - 1] + 1);
}

export function group(tree:Group, paths:Path[]):Group {
  if (!canGroup(paths) || !paths.every((p) => find(tree, p))) { return tree; }
  const next = clone(tree);
  const parent = find(next, parentOf(paths[0])) as Group;
  const idx = paths.map(last).sort((a, b) => a - b);
  const moved = parent.children.splice(idx[0], idx.length);
  parent.children.splice(idx[0], 0, { op: parent.op === 'and' ? 'or' : 'and', children: moved });
  return next;
}

// Note: ungrouping a group whose op differs from its parent's changes the query logic (UI concern).
export function ungroup(tree:Group, path:Path):Group {
  if (path.length === 0 || !isGroup(find(tree, path))) { return tree; }
  const next = clone(tree);
  const parent = find(next, parentOf(path)) as Group;
  parent.children.splice(last(path), 1, ...(find(next, path) as Group).children);
  return next;
}

// Conditions and nested-group headers in display order. A row at indexInParent > 0 shows (and edits)
// its parent's op, so every group's And/Or is visible: on its second child, condition or group.
export function layout(tree:Group):LayoutRow[] {
  const out:LayoutRow[] = [];
  const walk = (g:Group, path:Path) => g.children.forEach((child, i) => {
    const p = [...path, i];
    const base = { path: p, depth: path.length, parentPath: path, indexInParent: i, parentOp: g.op };
    if (isGroup(child)) {
      out.push({ kind: 'group', key: `g${p.join('.')}`, node: child, ...base });
      walk(child, p);
    } else {
      out.push({ kind: 'condition', key: child.key ?? p.join('.'), node: child, ...base });
    }
  });
  walk(tree, []);
  return out;
}

// Condition rows only; groups are addressed by path (e.g. row.parentPath).
export function rows(tree:Group):Row[] {
  return layout(tree).flatMap((r) => (r.kind === 'condition'
    ? [{ path: r.path, node: r.node, depth: r.depth, parentPath: r.parentPath, indexInParent: r.indexInParent, parentOp: r.parentOp }]
    : []));
}

// Copy of a tree (e.g. as loaded from the API) where every condition has a client-side key.
export function withKeys(tree:Group):Group {
  const next = clone(tree);
  const walk = (g:Group):void => g.children.forEach((c) => { if (isGroup(c)) { walk(c); } else { c.key ??= newKey(); } });
  walk(next);
  return next;
}

// Drops conditions that have no field yet (the starter row, half-filled rows) and the groups that
// become empty, so Run/Save only send complete conditions. The root group is always kept, and the
// client-side keys are stripped: this is the shape sent to the API.
export function pruneIncomplete(tree:Group):Group {
  const keep = (g:Group):Group => ({
    op: g.op,
    children: g.children.flatMap((c):TreeNode[] => {
      if (!isGroup(c)) { return c.field ? [{ field: c.field, operator: c.operator, values: [...c.values] }] : []; }
      const inner = keep(c);
      return inner.children.length ? [inner] : [];
    }),
  });
  return keep(tree);
}
