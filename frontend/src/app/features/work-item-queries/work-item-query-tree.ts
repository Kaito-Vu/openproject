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
export interface Condition { field:string; operator:string; values:string[] }
export interface Group { op:Op; children:TreeNode[] }
export type TreeNode = Condition|Group;
export type Path = number[];
export interface Row {
  path:Path; node:Condition; depth:number; parentPath:Path; indexInParent:number; parentOp:Op;
}

export const isGroup = (n:TreeNode):n is Group => 'children' in n;
export const emptyTree = ():Group => ({ op: 'and', children: [] });

const clone = <T>(v:T):T => structuredClone(v);
const at = (tree:Group, path:Path):TreeNode => path.reduce<TreeNode>((n, i) => (n as Group).children[i], tree);
const last = (p:Path) => p[p.length - 1];
const parentOf = (p:Path) => p.slice(0, -1);

function prune(g:Group):Group {
  g.children.forEach((c) => isGroup(c) && prune(c));
  g.children = g.children.filter((c) => !isGroup(c) || c.children.length > 0);
  return g;
}

export function addCondition(tree:Group, parent:Path):Group {
  const next = clone(tree);
  (at(next, parent) as Group).children.push({ field: '', operator: '=', values: [] });
  return next;
}

export function removeAt(tree:Group, path:Path):Group {
  const next = clone(tree);
  (at(next, parentOf(path)) as Group).children.splice(last(path), 1);
  return prune(next);
}

export function setOp(tree:Group, path:Path, op:Op):Group {
  const next = clone(tree);
  (at(next, path) as Group).op = op;
  return next;
}

export function updateCondition(tree:Group, path:Path, patch:Partial<Condition>):Group {
  const next = clone(tree);
  Object.assign(at(next, path), patch);
  return next;
}

export function canGroup(paths:Path[]):boolean {
  if (paths.length < 2) { return false; }
  const parent = parentOf(paths[0]).join('.');
  if (!paths.every((p) => parentOf(p).join('.') === parent)) { return false; }
  const idx = paths.map(last).sort((a, b) => a - b);
  return idx.every((v, i) => i === 0 || v === idx[i - 1] + 1);
}

export function group(tree:Group, paths:Path[]):Group {
  if (!canGroup(paths)) { return tree; }
  const next = clone(tree);
  const parent = at(next, parentOf(paths[0])) as Group;
  const idx = paths.map(last).sort((a, b) => a - b);
  const moved = parent.children.splice(idx[0], idx.length);
  parent.children.splice(idx[0], 0, { op: parent.op === 'and' ? 'or' : 'and', children: moved });
  return next;
}

export function ungroup(tree:Group, path:Path):Group {
  if (path.length === 0 || !isGroup(at(tree, path))) { return tree; }
  const next = clone(tree);
  const parent = at(next, parentOf(path)) as Group;
  parent.children.splice(last(path), 1, ...(at(next, path) as Group).children);
  return next;
}

export function rows(tree:Group):Row[] {
  const out:Row[] = [];
  const walk = (g:Group, path:Path) => g.children.forEach((child, i) => {
    const p = [...path, i];
    if (isGroup(child)) {
      walk(child, p);
    } else {
      out.push({ path: p, node: child, depth: path.length, parentPath: path, indexInParent: i, parentOp: g.op });
    }
  });
  walk(tree, []);
  return out;
}
