# Work Item Query Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone Azure DevOps-style query editor page: nested And/Or condition groups, Run query, Flat/Tree results, save/load queries.

**Architecture:** A new persisted model `WorkItemQuery` stores the condition tree as JSON. At run time a compiler turns the tree into one SQL boolean expression (reusing each existing work-package filter's `#where`), and a *transient* `Query` object carries that SQL (`Query#filter_tree_sql`) so the existing `Query::Results` / `QueryRepresenter` machinery does permissions, columns, sorting and paging. Persisted `Query` rows and their flat AND behaviour are untouched. The UI is an Angular standalone component embedded in a Rails page as a custom element (`angular_component_tag`).

**Tech Stack:** Rails 8.1 (Grape API v3, ActiveRecord, RSpec, FactoryBot), Angular (standalone components, Vitest via `ng test --watch=false`; there is no `toBeTrue/toBeFalse`, use `toBe(true/false)`).

**Spec:** `docs/superpowers/specs/2026-10-09-work-item-query-editor-design.md`

## Global Constraints

- Tree limits: depth <= 5 (root group = depth 1), <= 50 conditions.
- Condition leaf: `{"field": String, "operator": String, "values": [String]}`; group: `{"op": "and"|"or", "children": [node]}`; root is always a group.
- Mode values: exactly `"flat"` or `"tree"`.
- Conditions store **API field ids** (`status`, `type`, `assignee`, `customField12`, as listed by `/api/v3/queries/filters`). The compiler converts them to filter keys with `::API::Utilities::QueryFiltersNameConverter.to_ar_name(id, refer_to_ids: true)` (registered keys are AR names such as `status_id`, `type_id`).
- The transient `Query` built from a tree is never saved or `dup`ed (the filter serializer would collapse same-field filters).
- Within `API::V3::WorkItemQueries`, always reference app classes as `::WorkItemQueries::...`.
- Filters that use a non-symbol `joins` or a `from` cannot be used inside an OR group (rejected with `WorkItemQueries::Compiler::InvalidTree`).
- Do not change behaviour of persisted `Query` when `filter_tree_sql` is nil.
- Permissions: results always go through `WorkPackage.visible` (already done by `Query::Results#work_packages`).
- New files carry the standard OpenProject copyright header (copy from any file in `app/models`).
- Migration class base: `ActiveRecord::Migration[8.1]`; latest existing migration is `20261001120000`.

## File Structure

Backend
- `db/migrate/20261009100000_create_work_item_queries.rb` - table
- `app/models/work_item_query.rb` - model, validations
- `app/services/work_item_queries/tree_validator.rb` - shape/limit checks (pure Ruby)
- `app/services/work_item_queries/compiler.rb` - tree -> SQL + leaf filters
- `app/services/work_item_queries/build_query.rb` - WorkItemQuery -> transient `Query`
- `app/models/query.rb` (modify) - `filter_tree_sql`, `statement`
- `app/models/query/results.rb` (modify) - `filter_merges`
- `app/models/queries/filters/base.rb` (modify) - split `apply_to`
- `lib/api/v3/work_item_queries/work_item_queries_api.rb` - CRUD + execute
- `lib/api/v3/root.rb` (modify) - mount
- `app/models/work_item_query_favorite.rb` - per-user favorite flag
- `app/controllers/work_item_queries_controller.rb`, `app/views/work_item_queries/{index,editor}.html.erb`, `config/routes.rb`, `config/initializers/permissions.rb`, `config/initializers/menus.rb` (modify) - host pages (`/queries` list, `/queries/editor` editor)

Frontend (`frontend/src/app/features/work-item-queries/`)
- `work-item-query-tree.ts` (+ `.spec.ts`) - pure tree operations
- `work-item-query.service.ts` - API calls
- `work-item-query-editor.component.ts/.html/.sass` - page
- `work-item-condition-row.component.ts` - one row (field/operator/value)
- `work-item-results.component.ts` - flat/tree table
- `work-item-query-list.component.ts/.html` (+ `work-item-query-list.ts` with a pure `groupAndFilter` helper and spec) - the Queries list screen
- `frontend/src/app/app.module.ts` (modify) - register `opce-work-item-query-editor`

## Deviations from the spec (decided while planning, from reading the code)

1. Results are rendered by a small own table (id, type, subject, status, assignee + chosen columns) fed by the `QueryRepresenter` response, not by the full WP table, which is coupled to the work-package "query space" services.
2. Tree mode nests returned rows by `parent` link; rows whose parent is not in the result are shown as roots (no extra ancestor fetch in v1).
3. Query keeps persisted `Query` untouched except one optional attribute (`filter_tree_sql`); the spec said "no change to Query" - this is the minimum hook that lets `Query::Results` be reused.

---

### Task 1: Migration and `WorkItemQuery` model

**Files:**
- Create: `db/migrate/20261009100000_create_work_item_queries.rb`, `app/models/work_item_query.rb`, `app/services/work_item_queries/tree_validator.rb`
- Test: `spec/models/work_item_query_spec.rb`, `spec/services/work_item_queries/tree_validator_spec.rb`

**Interfaces:**
- Produces: `WorkItemQuery` columns `name, user_id, updated_by_id, project_id, public, mode, columns, sort_criteria, tree` (+ timestamps); `belongs_to :updated_by` (class `User`); `WorkItemQueryFavorite(user_id, work_item_query_id)` unique pair; `WorkItemQuery#favorite_of?(user)`; `WorkItemQuery.visible(user)`; `WorkItemQueries::TreeValidator.errors(tree) -> Array<String>` (empty when valid); constants `WorkItemQuery::MAX_DEPTH = 5`, `MAX_CONDITIONS = 50`, `EMPTY_TREE = {"op" => "and", "children" => []}`.

- [ ] **Step 1: Write the failing validator spec**

```ruby
# spec/services/work_item_queries/tree_validator_spec.rb
require "spec_helper"

RSpec.describe WorkItemQueries::TreeValidator do
  def leaf(field = "status") = { "field" => field, "operator" => "=", "values" => ["1"] }

  def nest(depth)
    node = leaf
    (depth - 1).times { node = { "op" => "and", "children" => [node] } }
    node
  end

  it "accepts an empty root group" do
    expect(described_class.errors({ "op" => "and", "children" => [] })).to be_empty
  end

  it "accepts nested groups" do
    tree = { "op" => "and", "children" => [leaf, { "op" => "or", "children" => [leaf, leaf("type")] }] }
    expect(described_class.errors(tree)).to be_empty
  end

  it "rejects a non-group root" do
    expect(described_class.errors(leaf)).not_to be_empty
  end

  it "rejects an unknown op" do
    expect(described_class.errors({ "op" => "xor", "children" => [] })).not_to be_empty
  end

  it "rejects a condition without field or with non-array values" do
    bad = { "op" => "and", "children" => [{ "field" => "", "operator" => "=", "values" => [] }] }
    expect(described_class.errors(bad)).not_to be_empty
    bad = { "op" => "and", "children" => [{ "field" => "status", "operator" => "=", "values" => "1" }] }
    expect(described_class.errors(bad)).not_to be_empty
  end

  it "rejects trees deeper than MAX_DEPTH" do
    # nest(n) wraps a leaf in n-1 groups; with the root that makes n groups deep.
    deep = { "op" => "and", "children" => [nest(WorkItemQuery::MAX_DEPTH + 1)] } # 6 groups
    expect(described_class.errors(deep)).not_to be_empty
    ok = { "op" => "and", "children" => [nest(WorkItemQuery::MAX_DEPTH)] } # 5 groups
    expect(described_class.errors(ok)).to be_empty
  end

  it "rejects more than MAX_CONDITIONS conditions" do
    tree = { "op" => "and", "children" => Array.new(WorkItemQuery::MAX_CONDITIONS + 1) { leaf } }
    expect(described_class.errors(tree)).not_to be_empty
  end
end
```

Depth definition (matches the validator in Step 4): only groups count; the root group is depth 1 and each nested group adds 1. `nest(5)` inside the root = 5 groups = accepted, `nest(6)` = 6 groups = rejected.

- [ ] **Step 2: Run it, confirm failure**

Run: `bundle exec rspec spec/services/work_item_queries/tree_validator_spec.rb`
Expected: FAIL (`uninitialized constant WorkItemQueries` / `WorkItemQuery`).

- [ ] **Step 3: Migration**

```ruby
# db/migrate/20261009100000_create_work_item_queries.rb
class CreateWorkItemQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :work_item_queries do |t|
      t.string :name, null: false
      t.references :user, null: false, foreign_key: true
      t.references :updated_by, null: true, foreign_key: { to_table: :users }
      t.references :project, null: true, foreign_key: true
      t.boolean :public, null: false, default: false
      t.string :mode, null: false, default: "flat"
      t.jsonb :columns, null: false, default: %w[id type subject status assignee]
      t.jsonb :sort_criteria, null: false, default: [%w[id asc]]
      t.jsonb :tree, null: false, default: { "op" => "and", "children" => [] }
      t.timestamps
    end

    create_table :work_item_query_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :work_item_query, null: false, foreign_key: true
      t.timestamps
    end
    add_index :work_item_query_favorites, %i[user_id work_item_query_id], unique: true, name: "idx_wiq_favorites_unique"
  end
end
```

Before running, check a recent migration for timestamp conventions (`t.timestamps precision:`/`with time zone`) and follow it. The jsonb array default is serialized by Rails; if `db:migrate` complains, use `default: -> { "'[\"id\",\"type\",\"subject\",\"status\",\"assignee\"]'::jsonb" }`.

```ruby
# app/models/work_item_query_favorite.rb
class WorkItemQueryFavorite < ApplicationRecord
  belongs_to :user
  belongs_to :work_item_query
end
```

- [ ] **Step 4: Model and validator**

```ruby
# app/models/work_item_query.rb
class WorkItemQuery < ApplicationRecord
  MODES = %w[flat tree].freeze
  MAX_DEPTH = 5
  MAX_CONDITIONS = 50

  belongs_to :user
  belongs_to :updated_by, class_name: "User", optional: true
  belongs_to :project, optional: true
  has_many :favorites, class_name: "WorkItemQueryFavorite", dependent: :delete_all

  validates :name, presence: true, length: { maximum: 255 }
  validates :mode, inclusion: { in: MODES }
  validate :tree_shape

  scope :visible, ->(user) { where(user_id: user.id).or(where(public: true)) }

  def favorite_of?(user)
    favorites.exists?(user_id: user.id)
  end

  private

  def tree_shape
    WorkItemQueries::TreeValidator.errors(tree).each { |message| errors.add(:tree, message) }
  end
end
```

```ruby
# app/services/work_item_queries/tree_validator.rb
module WorkItemQueries
  module TreeValidator
    module_function

    # Returns a list of human readable problems; empty means valid.
    def errors(tree)
      problems = []
      count = 0
      walk = lambda do |node, depth|
        if node.is_a?(Hash) && node.key?("children")
          problems << "unknown op #{node['op'].inspect}" unless %w[and or].include?(node["op"])
          problems << "group nested deeper than #{WorkItemQuery::MAX_DEPTH}" if depth > WorkItemQuery::MAX_DEPTH
          children = node["children"]
          children.is_a?(Array) ? children.each { |c| walk.call(c, depth + 1) } : problems << "children must be an array"
        elsif node.is_a?(Hash) && node.key?("field")
          count += 1
          problems << "condition needs field and operator" if node["field"].blank? || node["operator"].blank?
          problems << "values must be an array" unless node["values"].is_a?(Array)
        else
          problems << "node must be a group or a condition"
        end
      end

      problems << "root must be a group" unless tree.is_a?(Hash) && tree.key?("children")
      walk.call(tree, 1) if problems.empty?
      problems << "more than #{WorkItemQuery::MAX_CONDITIONS} conditions" if count > WorkItemQuery::MAX_CONDITIONS
      problems.uniq
    end
  end
end
```

- [ ] **Step 5: Model spec**

```ruby
# spec/models/work_item_query_spec.rb
require "spec_helper"

RSpec.describe WorkItemQuery do
  let(:user) { create(:user) }

  it "is valid with defaults" do
    expect(described_class.new(name: "q", user:)).to be_valid
  end

  it "rejects unknown mode and bad tree" do
    expect(described_class.new(name: "q", user:, mode: "grid")).not_to be_valid
    expect(described_class.new(name: "q", user:, tree: { "op" => "xor", "children" => [] })).not_to be_valid
  end

  it "scopes visible to owner or public" do
    mine = described_class.create!(name: "mine", user:)
    pub = described_class.create!(name: "pub", user: create(:user), public: true)
    described_class.create!(name: "other", user: create(:user))
    expect(described_class.visible(user)).to contain_exactly(mine, pub)
  end

  it "tracks favorites per user" do
    query = described_class.create!(name: "q", user:)
    WorkItemQueryFavorite.create!(user:, work_item_query: query)
    expect(query.favorite_of?(user)).to be true
    expect(query.favorite_of?(create(:user))).to be false
  end
end
```

- [ ] **Step 6: Migrate and run**

Run: `bin/rails db:migrate` (development; this updates the tracked `db/structure.sql`), then `bin/rails db:migrate RAILS_ENV=test` and `bundle exec rspec spec/services/work_item_queries/tree_validator_spec.rb spec/models/work_item_query_spec.rb`
Expected: PASS. Include `db/structure.sql` in the commit.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20261009100000_create_work_item_queries.rb app/models/work_item_query.rb app/models/work_item_query_favorite.rb app/services/work_item_queries/tree_validator.rb spec/models/work_item_query_spec.rb spec/services/work_item_queries/tree_validator_spec.rb db/structure.sql
git commit -m "feat: add WorkItemQuery model with condition tree validation"
```

---

### Task 2: Compiler (tree -> SQL) and `Query` hook

This is the riskiest task. Do it before any UI.

**Files:**
- Create: `app/services/work_item_queries/compiler.rb`
- Modify: `app/models/query.rb` (`statement`, new attr), `app/models/query/results.rb:335-339` (`filter_merges`), `app/models/queries/filters/base.rb:116-123` (`apply_to`)
- Test: `spec/services/work_item_queries/compiler_spec.rb`, add a case to `spec/models/query_spec.rb`

**Interfaces:**
- Produces:
  - `WorkItemQueries::Compiler.new(query).call(tree) -> [String sql, Array<Queries::Filters::Base> leaves]`; raises `WorkItemQueries::Compiler::InvalidTree` (`< StandardError`).
  - `WorkItemQueries::Compiler.or_unsafe?(filter) -> Boolean`.
  - `Query#filter_tree_sql` (attr_accessor, String or nil).
  - `Queries::Filters::Base#apply_joins_to(scope)`.

- [ ] **Step 1: Write the failing compiler spec**

```ruby
# spec/services/work_item_queries/compiler_spec.rb
require "spec_helper"

RSpec.describe WorkItemQueries::Compiler do
  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:s1) { create(:status) }
  let(:s2) { create(:status) }
  let(:s3) { create(:status) }
  let(:t1) { create(:type) }
  let(:t2) { create(:type) }
  let!(:wp_t1_s1) { create(:work_package, project:, type: t1, status: s1) }
  let!(:wp_t1_s2) { create(:work_package, project:, type: t1, status: s2) }
  let!(:wp_t1_s3) { create(:work_package, project:, type: t1, status: s3) }
  let!(:wp_t2_s1) { create(:work_package, project:, type: t2, status: s1) }

  def cond(field, *ids) = { "field" => field, "operator" => "=", "values" => ids.map { it.id.to_s } }
  def group(op, *children) = { "op" => op, "children" => children }

  def run(tree)
    wiq = WorkItemQuery.new(name: "q", user:, project:, tree:)
    User.execute_as(user) { WorkItemQueries::BuildQuery.new(wiq, user:).call.results.work_packages.to_a }
  end

  it "ANDs top-level conditions" do
    expect(run(group("and", cond("type", t1), cond("status", s1)))).to contain_exactly(wp_t1_s1)
  end

  it "supports nested OR inside AND" do
    tree = group("and", cond("type", t1), group("or", cond("status", s1), cond("status", s2)))
    expect(run(tree)).to contain_exactly(wp_t1_s1, wp_t1_s2)
  end

  it "allows the same field twice in different branches" do
    tree = group("or", group("and", cond("type", t1), cond("status", s1)),
                 group("and", cond("type", t2), cond("status", s1)))
    expect(run(tree)).to contain_exactly(wp_t1_s1, wp_t2_s1)
  end

  it "returns everything for an empty tree (no implicit open-status filter)" do
    expect(run(group("and"))).to contain_exactly(wp_t1_s1, wp_t1_s2, wp_t1_s3, wp_t2_s1)
  end

  it "raises InvalidTree for an unknown field" do
    expect { run(group("and", { "field" => "nope", "operator" => "=", "values" => ["1"] })) }
      .to raise_error(described_class::InvalidTree)
  end

  describe ".or_unsafe?" do
    it "flags filters with string joins or a from clause" do
      expect(described_class.or_unsafe?(double(from: nil, joins: "INNER JOIN x ON x.id = 1"))).to be true
      expect(described_class.or_unsafe?(double(from: "(select 1) AS work_packages", joins: nil))).to be true
    end

    it "allows symbol joins and no joins" do
      expect(described_class.or_unsafe?(double(from: nil, joins: :status))).to be false
      expect(described_class.or_unsafe?(double(from: nil, joins: nil))).to be false
    end
  end
end
```

- [ ] **Step 2: Run, confirm failure**

Run: `bundle exec rspec spec/services/work_item_queries/compiler_spec.rb`
Expected: FAIL (`uninitialized constant WorkItemQueries::Compiler`).

- [ ] **Step 3: Split `Filters::Base#apply_to`**

Replace the body at `app/models/queries/filters/base.rb:116-123`:

```ruby
  def apply_to(query_scope)
    apply_joins_to(query_scope.where(where))
  end

  # Everything apply_to does except the where clause. Used by tree queries, whose
  # combined where is built separately.
  def apply_joins_to(query_scope)
    query_scope = query_scope.from(from) if from
    query_scope = query_scope.joins(joins) if joins
    query_scope = query_scope.left_outer_joins(left_outer_joins) if left_outer_joins
    query_scope
  end
```

(Order of `.where` vs `.from` changes only in sequence of builder calls; the resulting relation is identical.)

- [ ] **Step 4: `Query` hook**

In `app/models/query.rb` add near the other accessors: `attr_accessor :filter_tree_sql`, and replace `statement` (currently lines 416-423):

```ruby
  def statement
    return "1=0" unless valid?

    statement_clauses.compact_blank.join(" AND ")
  end
```

and add (private section is fine, `statement_filters` is already there at ~506):

```ruby
  # A condition tree (see WorkItemQueries::Compiler) replaces the AND-joined filter list;
  # the project limit still applies.
  def statement_clauses
    return statement_filters.map { |filter| "(#{filter.where})" } if filter_tree_sql.nil?

    ["(#{filter_tree_sql})", *[project_limiting_filter].compact.map { |filter| "(#{filter.where})" }]
  end
```

- [ ] **Step 5: `Results#filter_merges`** (`app/models/query/results.rb:335`)

```ruby
  def filter_merges
    query.filters.inject(::WorkPackage.unscoped) do |scope, filter|
      query.filter_tree_sql ? filter.apply_joins_to(scope) : filter.apply_to(scope)
    end
  end
```

- [ ] **Step 6: Compiler**

```ruby
# app/services/work_item_queries/compiler.rb
module WorkItemQueries
  # Turns a condition tree into a single SQL boolean expression and the list of
  # filter instances (needed by Query::Results for joins/includes).
  class Compiler
    class InvalidTree < StandardError; end

    def self.or_unsafe?(filter)
      filter.from.present? || !Array(filter.joins).all?(Symbol)
    end

    def initialize(query)
      @query = query
      @leaves = []
    end

    def call(tree)
      problems = TreeValidator.errors(tree)
      raise InvalidTree, problems.to_sentence if problems.any?

      sql = compile_group(tree, inside_or: false)
      [sql.presence || "TRUE", @leaves]
    end

    private

    def compile(node, inside_or:)
      node.key?("children") ? compile_group(node, inside_or:) : compile_condition(node, inside_or:)
    end

    def compile_group(group, inside_or:)
      inside_or ||= group["op"] == "or"
      parts = group["children"].map { |child| compile(child, inside_or:) }.compact_blank
      return nil if parts.empty?

      "(#{parts.join(" #{group['op'].upcase} ")})"
    end

    def compile_condition(node, inside_or:)
      filter = build_filter(node)
      if inside_or && self.class.or_unsafe?(filter)
        raise InvalidTree, "#{node['field']} cannot be used inside an OR group"
      end

      @leaves << filter
      "(#{filter.where})"
    end

    def build_filter(node)
      key = ::API::Utilities::QueryFiltersNameConverter.to_ar_name(node["field"], refer_to_ids: true)
      filter = ::Queries::WorkPackages::FilterSerializer.filter_for(key, no_memoization: true)
      filter.context = @query
      filter.operator = node["operator"]
      filter.values = node["values"]
      raise InvalidTree, "invalid condition on #{node['field']}" unless filter.available? && filter.valid?

      filter
    end
  end
end
```

Notes: (a) the registered filter keys are AR names (`status_id`, `type_id`), which is why the API-id -> AR-name conversion is needed; the spec's `cond("status", ...)`/`cond("type", ...)` use API ids on purpose. (b) `FilterSerializer.filter_for` falls back to a "non existing" filter for unknown keys; its `available?` is false, so the `raise` above fires (the "unknown field" test covers this). Verify the `QueryFiltersNameConverter.to_ar_name` signature in `lib/api/utilities/query_filters_name_converter.rb` before running.

- [ ] **Step 7: `BuildQuery`** (needed by the spec's `run` helper)

```ruby
# app/services/work_item_queries/build_query.rb
module WorkItemQueries
  # Builds an unsaved Query that carries the compiled tree, so the regular
  # Query::Results / QueryRepresenter pipeline can run it.
  class BuildQuery
    def initialize(work_item_query, user:)
      @wiq = work_item_query
      @user = user
    end

    def call
      # include_subprojects is NOT NULL and validated (query.rb:55); without it the
      # query is invalid and Query#statement returns "1=0".
      query = Query.new(name: @wiq.name, user: @user, project: @wiq.project,
                        include_subprojects: Setting.display_subprojects_work_packages?,
                        show_hierarchies: @wiq.mode == "tree",
                        column_names: @wiq.columns, sort_criteria: @wiq.sort_criteria)
      sql, leaves = Compiler.new(query).call(@wiq.tree)
      query.filters = leaves
      query.filter_tree_sql = sql
      query
    end
  end
end
```

- [ ] **Step 8: Run**

Run: `bundle exec rspec spec/services/work_item_queries/compiler_spec.rb`
Expected: PASS. (The default "open status" filter is only added by `Query.new_default`, not by `Query.new`, so the empty-tree case returns everything. If a result set is unexpectedly empty, check `query.valid?` and `query.errors` first.)

- [ ] **Step 9: Regression run for the touched legacy code**

Run: `bundle exec rspec spec/models/query_spec.rb spec/models/query spec/models/queries/work_packages`
Expected: PASS with no new failures.

- [ ] **Step 10: Commit**

```bash
git add app/services/work_item_queries app/models/query.rb app/models/query/results.rb app/models/queries/filters/base.rb spec/services/work_item_queries/compiler_spec.rb
git commit -m "feat: compile And/Or condition trees into a Query statement"
```

---

### Task 3: API v3 - CRUD and execute

**Files:**
- Create: `lib/api/v3/work_item_queries/work_item_queries_api.rb`
- Modify: `lib/api/v3/root.rb` (add `mount ::API::V3::WorkItemQueries::WorkItemQueriesAPI` next to `QueriesAPI`, line ~77)
- Test: `spec/requests/api/v3/work_item_queries_spec.rb`

**Interfaces:**
- Consumes: `WorkItemQuery`, `WorkItemQueries::BuildQuery`, `Compiler::InvalidTree`, `QueryRepresenterResponse#query_representer_response(query, params)`.
- Produces (JSON, plain not HAL):
  - `GET /api/v3/work_item_queries` -> `{ "items": [item] }` (own + public queries)
  - `PUT|DELETE /api/v3/work_item_queries/:id/favorite` -> 204
  - `POST /api/v3/work_item_queries` body item fields -> 201 item
  - `GET|PATCH|DELETE /api/v3/work_item_queries/:id`
  - `POST /api/v3/work_item_queries/execute` body `{tree, mode, columns, project_id?, pageSize?, offset?}` -> the standard Query representation (`_embedded.results._embedded.elements` = work packages, each with `_links.parent`).
  - item = `{id, name, mode, public, project_id, columns, sort_criteria, tree, user_id, favorite, updated_at, updated_by_name}`.
  - Errors: invalid tree -> 422 `{ "message": ... }`; not owner on update/delete -> 403; invisible -> 404.

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/api/v3/work_item_queries_spec.rb
require "spec_helper"
require "rack/test"

RSpec.describe "API v3 work_item_queries" do
  include API::V3::Utilities::PathHelper

  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:status) { create(:status) }
  let!(:wp) { create(:work_package, project:, status:) }
  let(:tree) { { op: "and", children: [{ field: "status", operator: "=", values: [status.id.to_s] }] } }

  before { login_as(user) }

  def post_json(path, body) = post(path, body.to_json, "CONTENT_TYPE" => "application/json")
  def patch_json(path, body) = patch(path, body.to_json, "CONTENT_TYPE" => "application/json")

  it "creates, lists, reads, updates and deletes" do
    post_json "/api/v3/work_item_queries", { name: "Mine", tree:, mode: "tree" }
    expect(last_response.status).to eq 201
    id = JSON.parse(last_response.body)["id"]

    get "/api/v3/work_item_queries"
    expect(JSON.parse(last_response.body)["items"].pluck("id")).to include(id)

    patch_json "/api/v3/work_item_queries/#{id}", { name: "Renamed" }
    expect(JSON.parse(last_response.body)["name"]).to eq "Renamed"

    delete "/api/v3/work_item_queries/#{id}"
    expect(last_response.status).to eq 204
    expect(WorkItemQuery.exists?(id)).to be false
  end

  it "rejects an invalid tree on create" do
    post_json "/api/v3/work_item_queries", { name: "x", tree: { op: "xor", children: [] } }
    expect(last_response.status).to eq 422
  end

  it "does not let other users update a private query" do
    other = WorkItemQuery.create!(name: "o", user: create(:user))
    patch_json "/api/v3/work_item_queries/#{other.id}", { name: "hacked" }
    expect(last_response.status).to eq(404).or eq(403)
  end

  it "executes an unsaved tree and returns matching work packages" do
    post_json "/api/v3/work_item_queries/execute", { tree:, mode: "flat", project_id: project.id }
    expect(last_response.status).to eq 200
    ids = JSON.parse(last_response.body).dig("_embedded", "results", "_embedded", "elements").pluck("id")
    expect(ids).to contain_exactly(wp.id)
  end

  it "returns 422 when the tree uses an unsupported filter in OR" do
    bad = { op: "or", children: [{ field: "nope", operator: "=", values: ["1"] }] }
    post_json "/api/v3/work_item_queries/execute", { tree: bad }
    expect(last_response.status).to eq 422
  end
end
```

(Request specs in this repo use `last_response` from rack-test for the API; if sibling specs in `spec/requests/api/v3` use `response`, follow them instead.)

- [ ] **Step 2: Run, confirm failure** (`404` routes).

- [ ] **Step 3: Implement the API**

```ruby
# lib/api/v3/work_item_queries/work_item_queries_api.rb
module API
  module V3
    module WorkItemQueries
      class WorkItemQueriesAPI < ::API::OpenProjectAPI
        resources :work_item_queries do
          helpers ::API::V3::Queries::Helpers::QueryRepresenterResponse

          helpers do
            ATTRS = %i[name mode public project_id columns sort_criteria tree].freeze

            def item(record)
              record.slice(:id, :name, :mode, :public, :project_id, :columns, :sort_criteria, :tree, :user_id)
                    .merge(favorite: record.favorite_of?(current_user),
                           updated_at: record.updated_at,
                           updated_by_name: (record.updated_by || record.user)&.name)
            end

            # Plain `params` slice: Grape `params do` blocks only bind to the next route,
            # so shared declarations would silently apply to just one verb.
            def attrs
              params.to_h.symbolize_keys.slice(*ATTRS).tap do |h|
                h[:tree] = JSON.parse(h[:tree].to_json) if h.key?(:tree)
              end
            end

            def find_visible!
              WorkItemQuery.visible(current_user).find_by(id: params[:id]) || raise(::API::Errors::NotFound)
            end

            def find_owned!
              record = find_visible!
              raise ::API::Errors::Unauthorized unless record.user_id == current_user.id

              record
            end

            def render_invalid(message)
              raise ::API::Errors::UnprocessableContent.new(message)
            end
          end

          # Authentication happens in after_validation, so authorize there too (a `before`
          # block would still see the anonymous user).
          after_validation do
            authorize_in_any_work_package(:view_work_packages)
          end

          get do
            { items: WorkItemQuery.visible(current_user).includes(:updated_by, :user).order(:name).map { item(it) } }
          end

          params do
            requires :name, type: String
          end
          post do
            record = WorkItemQuery.new(attrs.merge(user: current_user, updated_by: current_user))
            if record.save
              status 201
              item(record)
            else
              render_invalid(record.errors.full_messages.to_sentence)
            end
          end

          post :execute do
            wiq = WorkItemQuery.new(attrs.merge(name: "adhoc", user: current_user))
            query = begin
              ::WorkItemQueries::BuildQuery.new(wiq, user: current_user).call
            rescue ::WorkItemQueries::Compiler::InvalidTree => e
              render_invalid(e.message)
            end
            query_representer_response(query, params.slice(:pageSize, :offset).to_h.symbolize_keys)
          end

          route_param :id, type: Integer do
            get { item(find_visible!) }

            patch do
              record = find_owned!
              if record.update(attrs.merge(updated_by: current_user))
                item(record)
              else
                render_invalid(record.errors.full_messages.to_sentence)
              end
            end

            delete do
              find_owned!.destroy
              status 204
              body false
            end

            namespace :favorite do
              put do
                record = find_visible!
                WorkItemQueryFavorite.find_or_create_by!(user: current_user, work_item_query: record)
                status 204
                body false
              end

              delete do
                WorkItemQueryFavorite.where(user: current_user, work_item_query_id: find_visible!.id).delete_all
                status 204
                body false
              end
            end
          end
        end
      end
    end
  end
end
```

Add to `lib/api/v3/root.rb`: `mount ::API::V3::WorkItemQueries::WorkItemQueriesAPI` (next to `QueriesAPI`, ~line 77).

Notes for the implementer:
- `API::Errors::UnprocessableContent`, `Unauthorized` (403) and `NotFound` (404) live in `lib/api/errors/`; check the exact constructor of `UnprocessableContent` there and adapt `render_invalid`.
- Plain Hash returns are serialized by `API::Formatter` (`lib/api/formatter.rb`), so no representer is needed.
- `query_representer_response` receives a symbol-keyed Hash; if it raises, pass `{}` and drop paging for v1.
- The request spec also asserts `favorite`, `updated_by_name` and the favorite endpoints (below).

- [ ] **Step 3b: Add to the request spec**

```ruby
  it "lists favorite flag and last modifier, and toggles favorites" do
    post_json "/api/v3/work_item_queries", { name: "Fav", tree: }
    id = JSON.parse(last_response.body)["id"]

    put "/api/v3/work_item_queries/#{id}/favorite"
    expect(last_response.status).to eq 204
    get "/api/v3/work_item_queries"
    item = JSON.parse(last_response.body)["items"].find { it["id"] == id }
    expect(item["favorite"]).to be true
    expect(item["updated_by_name"]).to eq user.name

    delete "/api/v3/work_item_queries/#{id}/favorite"
    get "/api/v3/work_item_queries"
    expect(JSON.parse(last_response.body)["items"].find { it["id"] == id }["favorite"]).to be false
  end
```

- [ ] **Step 4: Run** `bundle exec rspec spec/requests/api/v3/work_item_queries_spec.rb` -> PASS. Adjust per the notes above only where a test fails.

- [ ] **Step 5: Commit**

```bash
git add lib/api/v3/work_item_queries lib/api/v3/root.rb spec/requests/api/v3/work_item_queries_spec.rb
git commit -m "feat: add work_item_queries API with execute endpoint"
```

---

### Task 4: Frontend tree operations (pure TS)

**Files:**
- Create: `frontend/src/app/features/work-item-queries/work-item-query-tree.ts`
- Test: `frontend/src/app/features/work-item-queries/work-item-query-tree.spec.ts`

**Interfaces:**
- Produces (all pure, immutable, input never mutated):
  `type Op = 'and'|'or'`, `interface Condition {field:string; operator:string; values:string[]}`, `interface Group {op:Op; children:TreeNode[]}`, `type TreeNode = Condition|Group`, `type Path = number[]`,
  `isGroup(n)`, `emptyTree():Group`, `addCondition(tree, parent:Path):Group`, `removeAt(tree, path):Group` (prunes empty groups), `setOp(tree, groupPath, op):Group`, `canGroup(paths):boolean`, `group(tree, paths):Group` (new group gets the opposite op of its parent), `ungroup(tree, path):Group`, `updateCondition(tree, path, patch:Partial<Condition>):Group`, `rows(tree):Row[]` with `Row = {path:Path; node:Condition; depth:number; parentPath:Path; indexInParent:number; parentOp:Op}`.

- [ ] **Step 1: Write the failing spec**

```ts
// work-item-query-tree.spec.ts
import {
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
});
```

- [ ] **Step 2: Run, confirm failure**

Run (from `frontend/`): `npx ng test --watch=false --include='**/work-item-query-tree.spec.ts'` (the runner is Vitest through Angular's `unit-test` builder; if `--include` is not passed through, run `npm test` and filter by name).
Expected: FAIL (module not found). Import `describe/it/expect` from `vitest` only if sibling specs do; otherwise rely on globals like they do.

- [ ] **Step 3: Implement**

```ts
// work-item-query-tree.ts
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
```

- [ ] **Step 4: Run** the spec -> PASS. Also `npx eslint frontend/src/app/features/work-item-queries` -> clean.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/app/features/work-item-queries
git commit -m "feat: add pure condition-tree operations for query editor"
```

---

### Task 5: Page host, API service and results (flat/tree)

**Files:**
- Create: `app/controllers/work_item_queries_controller.rb`, `app/views/work_item_queries/index.html.erb`
- Modify: `config/routes.rb` (add `resources :work_item_queries, only: :index, path: "queries/editor"` hmm - see below), `frontend/src/app/app.module.ts:357-360`
- Create: `frontend/src/app/features/work-item-queries/work-item-query.service.ts`, `work-item-results.component.ts`, `work-item-query-editor.component.ts`, `work-item-query-editor.component.html`
- Test: `work-item-results.component.spec.ts` (tree nesting helper), controller covered by Task 7 feature spec

**Interfaces:**
- Consumes: Task 3 API, Task 4 tree ops.
- Produces: custom element `opce-work-item-query-editor` with optional inputs `projectId:number|null` and `queryId:number|null`. `angular_component_tag` only writes `data-*` attributes and Angular Elements does not read them, so the component constructor must call `populateInputsFromDataset(this)` from `core-app/shared/components/dataset-inputs` (see `global-search-work-packages.component.ts:93` for the pattern); `WorkItemQueryService`: `list():Observable<Item[]>`, `execute(body):Observable<ExecuteResponse>`, `create(item)`, `update(id,patch)`, `remove(id)`; pure helper `nestByParent(rows:ResultRow[]):ResultRow[]` in `work-item-results.component.ts` (rows with `children`).

- [ ] **Step 1: Test the nesting helper first**

```ts
// work-item-results.component.spec.ts
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
```

Run it, see it fail, then implement `nestByParent` in `work-item-results.component.ts`:

```ts
export interface ResultRow { id:number; subject:string; type:string; status:string; assignee:string; parentId:number|null; children:ResultRow[] }

export function nestByParent(flat:Omit<ResultRow, 'children'>[]):ResultRow[] {
  const byId = new Map<number, ResultRow>(flat.map((r) => [r.id, { ...r, children: [] }]));
  const roots:ResultRow[] = [];
  byId.forEach((row) => {
    const parent = row.parentId != null ? byId.get(row.parentId) : undefined;
    (parent ? parent.children : roots).push(row);
  });
  return roots;
}
```

and the standalone `WorkItemResultsComponent` (`selector: 'op-work-item-results'`, inputs `rows:ResultRow[]`, `mode:'flat'|'tree'`) rendering a `<table>` with columns id/type/subject/status/assignee; in tree mode it renders `nestByParent(rows)` recursively with a `padding-left: depth*16px` on the subject cell (use `ng-template` + `ngTemplateOutlet`).

- [ ] **Step 2: Service**

```ts
// work-item-query.service.ts
import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { Group } from './work-item-query-tree';

export interface WorkItemQueryItem {
  id?:number; name:string; mode:'flat'|'tree'; public:boolean; project_id:number|null;
  columns:string[]; sort_criteria:string[][]; tree:Group;
}

@Injectable({ providedIn: 'root' })
export class WorkItemQueryService {
  private http = inject(HttpClient);
  private base = '/api/v3/work_item_queries';

  list():Observable<{ items:WorkItemQueryItem[] }> { return this.http.get<{ items:WorkItemQueryItem[] }>(this.base); }
  execute(body:Partial<WorkItemQueryItem>&{ pageSize?:number }):Observable<any> { return this.http.post(`${this.base}/execute`, body); }
  create(item:WorkItemQueryItem):Observable<WorkItemQueryItem> { return this.http.post<WorkItemQueryItem>(this.base, item); }
  update(id:number, patch:Partial<WorkItemQueryItem>):Observable<WorkItemQueryItem> { return this.http.patch<WorkItemQueryItem>(`${this.base}/${id}`, patch); }
  remove(id:number):Observable<void> { return this.http.delete<void>(`${this.base}/${id}`); }
}
```

`execute` response mapping (put in the editor component): for each `el` in `res._embedded.results._embedded.elements` produce `{ id: el.id, subject: el.subject, type: el._links.type.title, status: el._links.status.title, assignee: el._links.assignee?.title ?? '', parentId: el._links.parent?.href ? Number(el._links.parent.href.split('/').pop()) : null }`.

- [ ] **Step 3: Editor component (skeleton wired to Task 4 + service)**

`WorkItemQueryEditorComponent` (standalone, `selector: 'op-work-item-query-editor'`, imports `CommonModule, FormsModule, WorkItemResultsComponent, WorkItemConditionRowComponent`). State: `tree:Group = emptyTree()`, `mode:'flat'|'tree' = 'flat'`, `acrossProjects = false`, `results:ResultRow[] = []`, `error:string|null`, `saved:WorkItemQueryItem[]`, `selected:Set<string>` (path strings `"0.1"`), `currentId:number|null`, `name = ''`. Methods: `run()` (calls `service.execute({tree, mode, project_id: acrossProjects ? null : this.projectId})`, maps the response, sets `error = err.error?.message` on 422), `add()`, `remove(path)`, `group()` (`this.tree = group(this.tree, [...selected].map(parse))`), `ungroup(path)`, `toggleOp(row)` (`setOp(tree, row.parentPath, row.parentOp === 'and' ? 'or' : 'and')`), `save()` (create or update by `currentId`, prompting for `name`), `load(item)`, `revert()` (reload `load(lastLoaded)`). Template: toolbar buttons (Run query, Save, Revert, Export CSV, Copy URL - the last two are Task 6), "Type of query" `<select [(ngModel)]="mode">` flat/tree, checkbox "Query across projects", one `<op-work-item-condition-row>` per `rows(tree)` row (checkbox for selection, And/Or `<select>` shown when `indexInParent > 0` bound to `toggleOp`, left border + `margin-left: depth*24px`), "Add new clause" link, then `<op-work-item-results>`.

- [ ] **Step 4: Register and host**

```ts
// app.module.ts (inside registerCustomElements)
registerCustomElement('opce-work-item-query-editor', WorkItemQueryEditorComponent, { injector });
```

```ruby
# app/controllers/work_item_queries_controller.rb
class WorkItemQueriesController < ApplicationController
  before_action :require_login
  before_action :load_and_authorize_in_optional_project
  authorization_checked! :index

  def index; end

  def editor; end
end
```

```erb
<%# app/views/work_item_queries/editor.html.erb %>
<% html_title t("label_work_item_query_editor") %>
<%= angular_component_tag "opce-work-item-query-editor", inputs: { projectId: @project&.id, queryId: params[:id] } %>
```

```erb
<%# app/views/work_item_queries/index.html.erb - built in Task 7 %>
<% html_title t("label_work_item_queries") %>
<%= angular_component_tag "opce-work-item-query-list", inputs: { projectId: @project&.id, currentUserId: current_user.id } %>
```

Routing and authorization (all three are required, otherwise the page 403s):
- `config/routes.rb`, global and project scoped (next to the `work_packages` routes): `get "queries", to: "work_item_queries#index", as: :work_item_queries` and `get "queries/editor", to: "work_item_queries#editor", as: :work_item_query_editor`.
- `config/initializers/permissions.rb` (the `view_work_packages` permission, ~line 339, which maps `work_packages: %i[show index ...]`): add `work_item_queries: %i[index editor]`. `load_and_authorize_in_optional_project` calls `do_authorize({controller:, action:})`, which resolves through this map.
- Locale key `label_work_item_query_editor: "Query editor"` and `label_work_item_queries: "Queries"` in `config/locales/en.yml` (en only; crowdin handles the rest).

- [ ] **Step 5: Manual verification** (frontend components are hard to unit test here)

Run the app (`bin/dev`), open `/queries/editor` (before Task 7 the list page does not exist yet), add a clause, Run, switch Tree, confirm results. Record the observed behaviour in the commit message body.

- [ ] **Step 6: Commit** `feat: query editor page with run, flat/tree results`.

---

### Task 6: Condition row - field, operator, value (DECISION GATE)

The one piece that cannot be fully specified from reading the code: how to render field-specific value inputs (status list, user autocomplete, dates, booleans, custom fields).

**Files:**
- Create: `frontend/src/app/features/work-item-queries/work-item-condition-row.component.ts`

**Interfaces:**
- Consumes: Task 4 `Condition`. Produces: `<op-work-item-condition-row [condition] (changed)="..." (removed)="...">` emitting `Partial<Condition>`.

- [x] **Step 1 (spike, time-box 1h): Try reuse.** Render the existing `op-query-filter` (`frontend/src/app/features/work-packages/components/filters/query-filter/query-filter.component.ts`, inputs `filter:QueryFilterInstanceResource`, outputs `filterChanged`, `deactivateFilter`) for one condition inside the editor, building the `QueryFilterInstanceResource` with `QueryFiltersService`/`WorkPackageViewFiltersService.instantiate(...)` (see `query-filters.component.ts` `onFilterAdded`) and providing those services in the editor component `providers`. Success = a status filter shows its value multiselect and emits a value change.
- [x] **Step 2: Record the decision** in this plan (edit this task): REUSE or FALLBACK.

  **Decision (2026-10-09): FALLBACK.** `QueryFilterComponent` is `standalone: false` (attribute selector `[query-filter]`, declared in the WP NgModule) and injects `WorkPackageViewFiltersService`/`WorkPackageViewBaselineService`, which extend `WorkPackageViewBaseService` and inject `IsolatedQuerySpace`; that space and ~25 sibling view services are only provided by `wp-isolated-query-space.directive.ts`, and `instantiate()` reads `querySpace.available.filters`, filled from the loaded query form. Not run-verifiable here, so rejected. Fallback deviates from Step 3 (FALLBACK) on the endpoint: `GET /api/v3/queries/filter_instance_schemas/<id>` renders with `form_embedded: false`, which omits both the operator `allowedValues` and the values `allowedValues` href (see `SchemaRepresenter#schema_with_allowed_*_getter` and the "does not link to allowed values" examples in `query_filter_instance_schema_representer_spec.rb`). The row therefore loads all filter schemas once per page from `POST /api/v3/queries/form` (`_embedded.schema._embedded.filtersSchemas`, `form_embedded: true`, the same source the WP list uses) and fetches list options from each values `_links.allowedValues.href` (or takes the inline link array for custom options). Files: `work-item-filter-schema.ts` (+spec), `work-item-filter-schema.service.ts`, `work-item-condition-row.component.ts`.
- [ ] **Step 3 (REUSE):** adapt `filterChanged` output to `{field, operator, values}` using the filter's `id`, `operator.id`, `values.map(v => v.id ?? v)`; remove the standalone-only parts.
- [ ] **Step 3 (FALLBACK):** field `<select>` filled from `GET /api/v3/queries/filters` (`_embedded.elements[].id/name`); on field change fetch `GET /api/v3/queries/filter_instance_schemas/<id>` and take operators from `_embedded.filter...` / `_links.operator.allowedValues` and, per operator, `_dependencies[0].dependencies["/api/v3/queries/operators/<op>"].values` (`type` like `[]Status`, `_links.allowedValues`) for options; render `<select multiple>` for list types, `<input type=date>` for `Date`, checkbox for `Boolean`, text input otherwise; hide value input for operators `*`, `!*`, `o`, `c`, `t`, `w`. Verify the schema JSON shape against a real response first and adapt names.
- [ ] **Step 4: Manual verification** with fields: status (list), subject (text), due date (date), assignee (user list), one custom field.
- [ ] **Step 5: Commit** `feat: condition row for query editor`.

---

### Task 7: Queries list screen

Screen reference (Azure DevOps "Queries"): title "Queries"; tabs **Favorites** / **All**; toolbar **New query** and a **Filter by keywords** box; table with columns **Title** and **Last modified by**; collapsible sections **My Queries** and **Shared Queries**; each row has the query title (link to the editor), a favorite star, and "<name> updated <date>" with an initials avatar.

Not in this plan (listed in the screenshot): **New folder / nested folders** and **Import Work Items**. Folders need a `parent_id`/folder model plus drag and drop; import needs CSV/Excel mapping. Both are separate follow-ups.

**Files:**
- Create: `frontend/src/app/features/work-item-queries/work-item-query-list.ts`, `work-item-query-list.spec.ts`, `work-item-query-list.component.ts`, `work-item-query-list.component.html`
- Modify: `frontend/src/app/app.module.ts` (register `opce-work-item-query-list`), `work-item-query.service.ts` (favorites)
- Test: `work-item-query-list.spec.ts`, `spec/features/work_item_queries/query_list_spec.rb`

**Interfaces:**
- Consumes: Task 3 list/favorite/delete API, view `index.html.erb` from Task 5 (inputs `projectId`, `currentUserId`).
- Produces: `groupAndFilter(items:WorkItemQueryItem[], opts:{tab:'favorites'|'all'; keyword:string; currentUserId:number}):{ my:WorkItemQueryItem[]; shared:WorkItemQueryItem[] }`; `WorkItemQueryService.setFavorite(id:number, on:boolean):Observable<void>`. `WorkItemQueryItem` gains `user_id:number; favorite:boolean; updated_at:string; updated_by_name:string`.

- [ ] **Step 1: Failing spec for the pure helper**

```ts
// work-item-query-list.spec.ts
import { groupAndFilter } from './work-item-query-list';

const item = (over:any) => ({
  id: 1, name: 'Bugs', mode: 'flat', public: false, project_id: null, columns: [], sort_criteria: [],
  tree: { op: 'and', children: [] }, user_id: 1, favorite: false, updated_at: '2026-01-01T00:00:00Z',
  updated_by_name: 'A', ...over,
}) as any;

describe('groupAndFilter', () => {
  const items = [
    item({ id: 1, name: 'Bugs', user_id: 1 }),
    item({ id: 2, name: 'Assigned to me', user_id: 1, favorite: true }),
    item({ id: 3, name: 'Release bugs', user_id: 2, public: true, favorite: true }),
    item({ id: 4, name: 'Other private', user_id: 2, public: false }),
  ];

  it('splits own queries from shared public ones and hides private queries of others', () => {
    const out = groupAndFilter(items, { tab: 'all', keyword: '', currentUserId: 1 });
    expect(out.my.map((i) => i.id)).toEqual([2, 1]); // sorted by name: Assigned..., Bugs
    expect(out.shared.map((i) => i.id)).toEqual([3]);
  });

  it('shows only favorites on the favorites tab', () => {
    const out = groupAndFilter(items, { tab: 'favorites', keyword: '', currentUserId: 1 });
    expect(out.my.map((i) => i.id)).toEqual([2]);
    expect(out.shared.map((i) => i.id)).toEqual([3]);
  });

  it('filters by keyword, case-insensitively', () => {
    const out = groupAndFilter(items, { tab: 'all', keyword: 'BUGS', currentUserId: 1 });
    expect(out.my.map((i) => i.id)).toEqual([1]);
    expect(out.shared.map((i) => i.id)).toEqual([3]);
  });
});
```

Run `npx ng test --watch=false --include='**/work-item-query-list.spec.ts'` (from `frontend/`) -> FAIL (module not found).

- [ ] **Step 2: Implement the helper**

```ts
// work-item-query-list.ts
import { WorkItemQueryItem } from './work-item-query.service';

export interface ListOptions { tab:'favorites'|'all'; keyword:string; currentUserId:number }

export function groupAndFilter(items:WorkItemQueryItem[], opts:ListOptions) {
  const keyword = opts.keyword.trim().toLowerCase();
  const keep = (i:WorkItemQueryItem) => (opts.tab === 'all' || i.favorite)
    && (!keyword || i.name.toLowerCase().includes(keyword));
  const byName = (a:WorkItemQueryItem, b:WorkItemQueryItem) => a.name.localeCompare(b.name);
  const visible = items.filter(keep);

  return {
    my: visible.filter((i) => i.user_id === opts.currentUserId).sort(byName),
    shared: visible.filter((i) => i.user_id !== opts.currentUserId && i.public).sort(byName),
  };
}
```

(The list API only returns own + public queries, so the `public` check in `shared` is a second guard.) Run the spec -> PASS.

- [ ] **Step 3: Service additions** in `work-item-query.service.ts`: extend `WorkItemQueryItem` as in Interfaces and add

```ts
  setFavorite(id:number, on:boolean):Observable<void> {
    const url = `${this.base}/${id}/favorite`;
    return on ? this.http.put<void>(url, {}) : this.http.delete<void>(url);
  }
```

- [ ] **Step 4: Component.** `WorkItemQueryListComponent` (standalone, `selector: 'op-work-item-query-list'`, imports `CommonModule, FormsModule`; constructor calls `populateInputsFromDataset(this)` like the editor). State: `items`, `tab:'favorites'|'all' = 'all'`, `keyword = ''`, `collapsed = { my: false, shared: false }`, `loading`, `error`. `ngOnInit`: `service.list().subscribe(r => items = r.items)`. Getter `view = groupAndFilter(items, {tab, keyword, currentUserId})`. Methods: `toggleFavorite(item)` (optimistic: flip `item.favorite`, call `setFavorite`, revert + set `error` on failure), `remove(item)` (own queries only; `confirm()` first; then `service.remove`), `open(item)` -> `location.href = editorUrl + '?id=' + item.id`, `newQuery()` -> `location.href = editorUrl`, `initials(name)` (first letters of the first two words, uppercased), `editorUrl` = `projectId ? '/projects/' + projectId + '/queries/editor' : '/queries/editor'`.

Template (structure; plain HTML plus existing OpenProject utility classes, no new CSS framework):
- `<h1>Queries</h1>`
- tab buttons `Favorites` / `All` (`[class.-active]="tab === 'x'"`, `(click)="tab = 'x'"`)
- toolbar: `<button (click)="newQuery()">New query</button>` and `<input type="search" placeholder="Filter by keywords" [(ngModel)]="keyword">`
- one `<table>`; header row `Title | Last modified by`; for each of `my` / `shared`: a section row with a chevron toggling `collapsed[...]` and the section name + count, then (unless collapsed) one row per query: mode icon, title as `<a>` calling `open(item)`, star `<button [attr.aria-pressed]="item.favorite" (click)="toggleFavorite(item)">`, trash button only for own rows, then a cell with the initials avatar and `{{ item.updated_by_name }} updated {{ item.updated_at | date:'shortDate' }}`
- empty states: "No queries yet - create one with New query" / "No favorites yet" per tab, and "No matches" when a keyword filters everything out.

Register in `app.module.ts`: `registerCustomElement('opce-work-item-query-list', WorkItemQueryListComponent, { injector });`.

- [ ] **Step 5: Feature spec**

```ruby
# spec/features/work_item_queries/query_list_spec.rb
require "spec_helper"

RSpec.describe "Queries list", :js do
  let(:user) { create(:admin) }
  let(:other) { create(:user) }
  let!(:mine) { WorkItemQuery.create!(name: "My bugs", user:, updated_by: user) }
  let!(:shared) { WorkItemQuery.create!(name: "Release bugs", user: other, updated_by: other, public: true) }
  let!(:private_other) { WorkItemQuery.create!(name: "Hidden", user: other) }

  before { login_as(user) }

  it "shows My and Shared sections, favorites tab and keyword filter" do
    visit "/queries"
    expect(page).to have_text("My bugs")
    expect(page).to have_text("Release bugs")
    expect(page).to have_no_text("Hidden")

    fill_in "Filter by keywords", with: "release"
    expect(page).to have_no_text("My bugs")

    fill_in "Filter by keywords", with: ""
    within(:xpath, "//tr[contains(., 'My bugs')]") { find("button[aria-pressed]").click }
    click_on "Favorites"
    expect(page).to have_text("My bugs")
    expect(page).to have_no_text("Release bugs")
  end

  it "opens the editor from New query" do
    visit "/queries"
    click_on "New query"
    expect(page).to have_current_path(%r{/queries/editor})
  end
end
```

- [ ] **Step 6: Run** the Vitest spec and `bundle exec rspec spec/features/work_item_queries/query_list_spec.rb`. Commit `feat: queries list screen with favorites and keyword filter`.

---

### Task 8: Export CSV, Copy URL, menu entry, editor feature spec

**Files:**
- Modify: `work-item-query-editor.component.ts/.html`, `config/initializers/menus.rb`, `config/locales/en.yml`
- Test: `spec/features/work_item_queries/query_editor_spec.rb`

- [ ] **Step 1: Back to list.** The editor shows a breadcrumb "Queries > <name or New query>" whose first part links to `/queries` (or `/projects/<id>/queries`); after Save the editor stays on the page and updates `currentId` and the URL (`history.replaceState` to `/queries/editor?id=<id>`).
- [ ] **Step 2: Export CSV.** Client-side: build CSV from `results` (id, type, subject, status, assignee), download via `Blob` + temporary `<a download="query.csv">`. Limits: only the rows loaded by Run (default page size 100 - set `pageSize: 500` in `execute`).
- [ ] **Step 3: Copy URL.** The `queryId` input (Task 5) loads the query on init; "Copy URL" copies `location.origin + '/queries/editor?id=' + currentId` via `navigator.clipboard.writeText`, disabled until saved.
- [ ] **Step 4: Menu entry.** In `config/initializers/menus.rb` (global menu ~line 65 and the project-scoped one ~line 795, next to the work packages entries) add a "Queries" item pointing to `work_item_queries_path` (project: `project_work_item_queries_path`), caption `:label_work_item_queries`; add the `config/locales/en.yml` keys if not yet present.
- [ ] **Step 5: Editor feature spec** (follow an existing JS feature spec in `spec/features/work_packages` for login/setup helpers):

```ruby
# spec/features/work_item_queries/query_editor_spec.rb
require "spec_helper"

RSpec.describe "Query editor", :js do
  let(:user) { create(:admin) }
  let(:project) { create(:project) }
  let(:open_status) { create(:status) }
  let(:closed_status) { create(:status) }
  let!(:wp_open) { create(:work_package, project:, status: open_status, subject: "Open one") }
  let!(:wp_closed) { create(:work_package, project:, status: closed_status, subject: "Closed one") }

  before { login_as(user) }

  it "runs a saved OR query" do
    visit "/projects/#{project.identifier}/queries/editor"

    click_on "Add new clause"
    # choose Status = open via the condition row, then add a second clause with OR and Status = closed
    # (use the row's field/operator/value controls built in Task 6)

    click_on "Run query"
    expect(page).to have_text("Open one")
    expect(page).to have_text("Closed one")

    click_on "Save query"
    fill_in "Name", with: "Both"
    click_on "Save"
    expect(WorkItemQuery.find_by(name: "Both").tree["children"].size).to eq 2
  end
end
```

Fill in the two comment lines using the selectors from the row component built in Task 6 (the spec cannot be finished before Task 6's decision).

- [ ] **Step 6: Run** `bundle exec rspec spec/features/work_item_queries` plus the whole backend set from Tasks 1-3. Commit `feat: export, copy URL and menu entry for query editor`.

---

## Final verification

- [ ] `bundle exec rspec spec/models/work_item_query_spec.rb spec/services/work_item_queries spec/requests/api/v3/work_item_queries_spec.rb spec/models/query_spec.rb spec/models/query spec/models/queries/work_packages`
- [ ] `npx eslint frontend/src/app/features/work-item-queries` and the Vitest specs from Tasks 4, 5 and 7
- [ ] Manual pass in the browser: nested OR group, Group/Ungroup, Tree mode, save/reload by URL, project vs across-projects
