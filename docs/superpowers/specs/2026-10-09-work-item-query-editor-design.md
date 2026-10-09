# Work Item Query Editor (Azure DevOps style)

## Goal
A standalone page to build work package queries with nested And/Or groups, run them, view results as Flat list or Tree (parent/child), and save/share queries.

## Why a new model
`Query#statement` (app/models/query.rb) joins all filters with AND and stores them as a flat list. Changing it would affect the WP table, boards, widgets and API v3. The editor therefore owns its condition tree.

## Data
Table `work_item_queries`: `name`, `user_id`, `project_id` (nullable = across projects), `public` (bool), `mode` (`flat`|`tree`), `columns` (json), `sort_criteria` (json), `tree` (json).

`tree` node:
- group: `{ "op": "and"|"or", "children": [node, ...] }`
- condition: `{ "field": "status", "operator": "=", "values": ["1"] }`

Limits: depth <= 5, <= 50 conditions.

## Execution
`WorkItemQueries::CompileService` walks the tree, calls the existing filter classes' `where` for each condition, and joins with AND/OR in parentheses. It runs on `WorkPackage.visible(user)` (and project scope when set), so permissions stay as they are. Validation: field/operator must be known filters; filters that cannot be combined with OR (join/subquery based) are rejected with an explicit error.

Tree mode: matched work packages nested by parent; non-matching ancestors included for context (same behaviour as OpenProject hierarchy mode).

## API (v3)
- CRUD `/api/v3/work_item_queries`
- `POST /api/v3/work_item_queries/execute` (ad-hoc tree) and `GET /:id/results`; both return the standard work package collection.

## Frontend
New Angular page (routes `/queries/editor`, `/projects/:id/queries/editor`), layout as the Azure DevOps editor:
- rows: And/Or, Field, Operator, Value, +/x, indentation per group; multi-select rows -> Group / Ungroup
- toolbar: Run query, Save, Revert, Column options, Export CSV, Copy URL
- Type of query: Flat list / Tree; "Query across projects" checkbox
- Field/Operator/Value inputs reuse existing filter value components if they can be hosted outside the WP query space, otherwise a schema-driven fallback (decision gate in the plan).
- Results use a small own table (flat, or nested by parent in Tree mode; rows whose parent is not in the result are roots), fed by the QueryRepresenter response of a transient `Query`.
- Queries list screen at `/queries` (Azure DevOps style): Favorites/All tabs, New query, keyword filter, collapsible My Queries / Shared Queries with favorite star and "last modified by" (needs `updated_by_id`, `work_item_query_favorites`).

## Out of scope (later)
Query folders/nested folders, drag and drop, "Import Work Items" (both visible in the list screenshot); "Work items and direct links" and link-type "Tree of work items"; query folders/permissions; Charts tab.

## First risk to retire
Compile service against main filters (status, type, assignee, dates, custom fields) before any UI work.

## Testing
Unit spec for compiler (and/or/nested/permissions/rejected filters), request specs for API, feature spec: add condition, group, Run, switch Tree, Save.

## Plan-time changes
Persisted `Query` gets one optional attribute (`filter_tree_sql`) so `Query::Results` can be reused; conditions store API field ids and are converted to filter keys by the compiler.
