# Issue View — Design Spec (Feature 04)

Nguồn: [docs/ideas/idea-04.md](../../ideas/idea-04.md) · Ngày: 2026-10-06 · Module: `modules/issue_view` · Phụ thuộc mềm: F02 `field_rules`, F03 `screens` (F01 không phải điều kiện cứng) · Phạm vi: **backend chỉ đọc** (API v3 + OpenAPI + test). Frontend Vue/React nằm ngoài repo.

## 0. Tóm tắt quyết định

| Chủ đề | Quyết định |
|---|---|
| Bản chất | Lớp trình bày **chỉ đọc** trên Work Package native. Không model, bảng, migration, route ghi. |
| Endpoint V1 | `GET /api/v3/work_packages/{id}/issue_view` và `GET /api/v3/work_packages/{id}/issue_view/activities`. |
| Relations / transitions / attachments / watchers | Không bọc lại; frontend dùng `_links` native. F04 chỉ cung cấp `counts`, `parent`, `permissions`. |
| Ghi | Luôn qua API v3 native (`PATCH` work package, `POST` activities, `PATCH` activities). |
| Layout | `Screens::Resolver.for(project, type, :view)` (F03); không có/lỗi ⇒ layout native từ schema. |
| Quyền | Dẫn xuất từ link/contract native; **không** tự cài authorization. 404 khi không thấy, không bao giờ 403. |
| Cache | `Cache-Control: private, no-cache` + `Vary`; **không** ETag/304 ở V1. |
| Fail-open | Lỗi F02/F03/builder ⇒ layout native + `reason: "error"`, vẫn 200. Endpoint activity không fail-open. |

## 1. Đối chiếu code (đã kiểm chứng)

| # | Chủ đề | Thực trạng (file) | Hệ quả |
|---|---|---|---|
| E1 | Mount route | `add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id do mount … end` (`lib/open_project/plugins/acts_as_op_engine.rb:229`; ví dụ `modules/costs/lib/costs/engine.rb:282-284`). Class con chạy trong `route_param :id` ⇒ thừa kế `after_validation`: `@work_package = WorkPackage.visible.find(id)` + `authorize_in_work_package(:view_work_packages){ raise NotFound }` (`lib/api/v3/work_packages/work_packages_api.rb:66-81`). `{id}` là String: id số **hoặc** semantic (`PROJ-42`). | Mount như costs; **không** `authorize` riêng; dùng reader `work_package`. |
| E2 | Anonymous / 404 | Không thấy/không quyền/project archived ⇒ `NotFound` (404); `login_required` + anonymous ⇒ 401 `Unauthenticated` (`lib/api/root_api.rb:72-77`); anonymous vào được chỉ khi role Anonymous có `view_work_packages`. F03 dùng `authorize_logged_in` (anonymous ⇒ 403) — **không áp dụng**. | Theo native; bảng lỗi §7. |
| E3 | Activities native | `get` trả `Activities::ActivityCollectionRepresenter` (**unpaginated**), nguồn `work_package.journals.internal_visible.meeting_cause_visible.includes(:data, :customizable_journals, :attachable_journals, :storable_journals, :bcf_comment)`; không đọc `offset/pageSize/filters/sortBy` (`activities_by_work_package_api.rb:38-58`, `activity_collection_representer.rb:32`). Không có DELETE; `PATCH /activities/{id}`; POST nhận `internal`. | F04 tự dựng collection phân trang (E4). |
| E4 | Phân trang | `offset` = số trang 1-based, `<1`/không số ⇒ trang 1; `pageSize`: `-1` hoặc `> apiv3_max_page_size` ⇒ kẹp, `0`/không số ⇒ trang rỗng (total đúng), **âm khác −1 không được validate** (`lib/api/decorators/offset_paginated_collection.rb:41-45`, `lib/api/utilities/url_props_parsing_helper.rb:34-60`, `lib/api/v3/utilities/endpoints/index.rb:92-116`). `sortBy`/`filters` sai tên/toán tử ⇒ 400 `InvalidQuery`; **JSON hỏng không được map ⇒ 500** (`lib/api/root_api.rb:310,329`; tiền lệ rescue `lib/api/v3/attachments/attachments_by_container_api.rb:68`). | Dùng `OffsetPaginatedCollection`; tự `rescue JSON::ParserError` ⇒ 400; tự chặn `pageSize` âm ≠ −1 ⇒ 400. |
| E5 | Journal | `journal.details` = `get_changes` (`lib_static/plugins/acts_as_journalized/lib/journal_changes.rb:32-53`): `HashWithIndifferentAccess {key => [old,new]}`, thứ tự chèn cố định (cause, cột data, `attachments_N`, custom comments, `custom_fields_N`, project phases, target/observed versions, `file_links_N`, participants, agenda items). `render_detail(detail, html:, only_path:, activity_page:)` (`journal_formatter.rb:103-125`) trả **một câu hoàn chỉnh** (không tách from/to), `nil` khi không có formatter; formatter đã che đối tượng không xem được bằng placeholder (`named_association.rb:57-75`) và field không có quyền (`custom_field` view_permission). Field người (`assigned_to_id`, `author_id`, `responsible_id`) luôn hiện tên (`public_named_association.rb`). `attachments_N`: `[nil, fn]` thêm, `[fn, nil]` gỡ, id ở hậu tố. `cause` = `{cause: [nil, hash]}`; thay đổi relation **không** có detail riêng, chỉ có journal `cause` (+ thay đổi ngày). `version_id` bị bỏ. | Mapping §5.3. |
| E6 | Internal / meeting | `internal_visible` (`app/models/work_package/journalized.rb:36-45`): trả `all` nếu token EE `internal_comments` + project `enabled_internal_comments` + `User.current` có `view_internal_comments`, ngược lại `where(internal: false)`. `meeting_cause_visible` (`modules/meeting/.../journal_patch.rb:39-46`). Cause meeting ẩn ⇒ formatter trả `""`. | FR-14; dùng `User.current` trong request. |
| E7 | Link WP representer | `update` = POST tới form (`work_package_representer.rb:67`); PATCH trực tiếp = **`updateImmediately`** (`:83`); `delete` `:93`; `addWatcher` `:231`, `removeWatcher` `:241`; `addRelation` `:250`; `addComment` `:279`; `addAttachment` ở `lib/api/v3/attachments/attachable_representer_mixin.rb:58`; `logTime` ở `modules/costs/lib/costs/engine.rb:291` (khi `log_time_allowed?`). | Bảng quyền §4.4. |
| E8 | Status cho phép | `WorkPackages::BaseContract#assignable_statuses` (`app/contracts/work_packages/base_contract.rb:188`) ⇒ `schema.status.allowedValues` (`specific_work_package_schema.rb:55`). Không có `new_statuses_allowed_to`. | `permissions.transition`. |
| E9 | Identifier | `Setting.work_packages_identifier` (`config/constants/settings/definition.rb:1491`); `Setting::WorkPackageIdentifier.semantic?`; cột `work_packages.identifier`; `WorkPackage#display_id` (`app/models/work_package/semantic_identifier.rb:197`). | `identifier = display_id`. |
| E10 | F03 | `Screens::Resolver.for(project, type, context)` ⇒ `ResolvedScreen = Data.define(:source, :reason, :context, :screen, :sections, :state_source, :diagnostics)`; `source`, `reason` là String; field `{key,label,position,width,state}`; section `{id,name,position,fields}` (id số); `FALLBACKS view: [view, edit]`; fail-open: `native(:error, …, error: true)`; `diagnostics` (snake_case) = `{unavailable, hidden_but_placed, required_not_placed, not_visible, skipped, empty_create_screen, error}` (`modules/screens/app/services/screens/resolver.rb:55,262-319`; `resolved_screen.rb:31`). | Ánh xạ §4.6. |
| E11 | Counts — visible | `WorkPackage.visible(user)` (`app/models/work_package.rb:86`); `Relation.visible(user, work_package_focus_scope:)` lọc **cả hai đầu** (`app/models/relations/scopes/visible.rb:49`; `wp.relations.visible(user)` ở `app/models/work_packages/relations.rb:41`); watchers cần `view_work_package_watchers` (project-level, `config/initializers/permissions.rb:507`; representer `:224-227`; **không có** `Watcher.visible`); attachments: `view_permission` mặc định = `view_#{name.pluralize.underscore}` = **`view_work_packages`** (`acts_as_attachable.rb:126-128`), ẩn khi `project.deactivate_work_package_attachments?` (`work_package.rb:310`); children: representer dùng `children.select(&:visible?)` (`work_package_representer.rb:807`). `costs`/`backlogs` không đổi các quy tắc này. | FR-10. |
| E12 | Engine/module | Mẫu `modules/screens`: `OpenProject::Screens::Engine` (`ActsAsOpEngine`, `register … bundled: true`, `config.to_prepare { assert_core_dependencies! }`), gem `openproject-screens` đăng ký ở `Gemfile.modules:35` (`path: 'modules/screens'`), cấu trúc `app/ config/ db/ lib/ spec/`. | Module `openproject-issue_view` theo mẫu; `assert_core_dependencies!` cho các điểm tựa ở §8. |
| E13 | Tên | `issue_view` không đụng tên nào; `/api/v3/views` đã tồn tại (resource Query view) ⇒ không dùng `view`. | Giữ `issue_view`. |

**Cần kiểm lại khi implement (rủi ro nhỏ):** (a) hành vi project archived là suy từ scope `allowed_to` (`app/models/projects/scopes/allowed_to.rb`) ⇒ có test chạy thật; (b) `JournalFormatter` có cần `User.current` thiết lập đúng khi chạy trong Grape (đã có tiền lệ ở `activity_property_formatters.rb`) ; (c) `Rails.error.report` đã dùng ở F03 — tái sử dụng cách gọi.

## 2. Mục tiêu và phạm vi

In (V1): endpoint `issue_view`, endpoint `issue_view/activities`, `IssueView::Builder/Permissions/ActivityNormalizer`, OpenAPI, test (unit/request/contract/authz/leak/query-count), i18n, feature flag.

Out: endpoint ghi (mọi loại), endpoint `relations`/`transitions` riêng, wrap attachments/watchers, emoji reaction, resolver tên cho `raw.from/to` (Q-H), `transitionScreen` (Q-C), search/dashboard/bulk/advanced linking, frontend, bảng/migration, ETag, sửa core.

## 3. Kiến trúc

```text
GET /api/v3/work_packages/{id}/issue_view[/activities]
  └ WorkPackagesAPI route_param :id  (visible + view_work_packages ⇒ NotFound)
      └ API::V3::IssueView::IssueViewAPI
          ├ IssueView::Builder.call(work_package, user)          # payload khởi tạo
          │    ├ Screens::Resolver.for(project, type, :view)     # optional (guard)
          │    ├ schema native (project,type) → dataType/writable/_attributeGroups
          │    ├ IssueView::Permissions.for(work_package, user)
          │    └ IssueView::Counts.for(work_package, user)
          └ IssueView::ActivityNormalizer (journals → events, phân trang theo journal)
```

* Không patch core; không `prepend`. Boot guard `OpenProject::IssueView.assert_core_dependencies!` kiểm các điểm tựa ở §8 (fail sớm trong `to_prepare`).
* Phụ thuộc mềm: `defined?(::Screens::Resolver)` / `defined?(::FieldRules::Resolver)`; gói trong `fail_open` giống `Screens::Resolver#fail_open` (log `OpenProject.logger.error` + `Rails.error.report(e, handled: true, context: {…})`).
* Cache chỉ trong request (`RequestStore`), không `Rails.cache`.

## 4. Hợp đồng `GET /api/v3/work_packages/{id}/issue_view`

`_type: "IssueView"`. Ví dụ đầy đủ: xem `docs/ideas/idea-04.md` §6; OpenAPI là nguồn chính (§9).

### 4.1 Quy ước (FR-01)

camelCase, `_type`, HAL `_links`, thời gian ISO-8601 UTC. Id trong body là số nguyên. `key` của field **snake_case** như F03 (`due_date`, `custom_field_12`).

### 4.2 Định danh và header (FR-02, FR-03)

* `identifier = work_package.display_id`; `id` = id số. Không lưu, không cache.
* `header` luôn có đủ 5 khoá `type, status, priority, assignee, author` (`null` nếu chưa gán; mỗi phần tử `{id, name, _links.self}`; `status` thêm `isClosed`). Header **không** áp F02 `hidden`, không có `editable`. Nếu field cùng khoá có trong `sections`, giá trị bằng nhau.
* `subject` ở cấp gốc.

### 4.3 Layout (FR-04, FR-05, FR-07, FR-13)

Thuật toán `Builder`:

1. `project = work_package.project`, `type = work_package.type`.
2. `resolved = fail_open { Screens::Resolver.for(project, type, :view) }` nếu F03 có; không có module ⇒ `native`, `reason: "module_disabled"`.
3. `source == "screen"` ⇒ lấy `resolved.sections` (id → String); mỗi field gắn `dataType`, `value`, `editable`, `editableReason`; `state` giữ từ F03 (đã gắn F02), `reason: null`.
4. `source == "native"` (kể cả lỗi): dựng từ `schema` native của (project, type): mỗi `WorkPackageFormAttributeGroup` ⇒ một section `{id: group key, name: group name, position: index+1}`, field `{width: "full", state: null}`. Group `query`/bảng liên quan **bỏ qua** (V1). `reason` = `resolved.reason` (`no_scheme`, `scheme_inactive`, `type_not_in_scheme`, `no_usable_screen`, `error`) hoặc `module_disabled`. Lỗi builder ngoài F03 ⇒ cũng `reason: "error"`.
5. Field không khả dụng/không xem được (custom field tắt, thiếu quyền; F03 đã loại phần của nó): loại khỏi `fields`.
6. `reason: "error"` là tín hiệu suy giảm duy nhất cho client.

`diagnostics` (FR-12): **chỉ admin**, camelCase, chỉ 2 khoá `unavailable[]`, `hiddenButPlaced[]` (mảng key, ánh xạ từ `unavailable`, `hidden_but_placed` của F03). Các khoá khác của F03 (`not_visible`, `required_not_placed`, `skipped`, `empty_create_screen`, `error`) **không** đưa ra. Người không phải admin: **không có khoá `diagnostics`**.

### 4.4 Quyền và `editable` (FR-08, FR-09)

`IssueView::Permissions` là nơi duy nhất tra quyền, nguồn là link/contract của native (dựng bằng `API::V3::WorkPackages::WorkPackageRepresenter` đã có hoặc gọi trực tiếp contract; spec chọn cách rẻ hơn **không** N+1 và ghi lại).

| khoá | điều kiện |
|---|---|
| `view` | `true` |
| `edit` | có link `updateImmediately` (hoặc `update`) |
| `delete` | có `delete` |
| `comment` | có `addComment` |
| `transition` | `edit` ∧ `assignable_statuses` có ≥1 status khác status hiện tại (E8) |
| `addRelation` | có `addRelation` |
| `manageWatchers` | có `addWatcher` hoặc `removeWatcher` |
| `addAttachment` | có `addAttachment` |
| `logTime` | có `logTime` (module costs); module tắt ⇒ `false` |

Cả 9 khoá luôn có, kiểu boolean. `_links` trong payload (`updateImmediately`, `addComment`, …) chỉ xuất hiện khi quyền tương ứng `true`; `allowedStatuses` = link form native `POST /work_packages/{id}/form`.

`editable` (mỗi field): `permissions.edit ∧ schema[key].writable ∧ ¬(state.readOnly)`; với `status`: `editable ⇔ permissions.transition`. `editable = true ⇒ editableReason = null`; ngược lại **một** lý do theo ưu tiên `locked > no_permission > not_writable > read_only > workflow` (`locked` = native không cho sửa WP; `workflow` chỉ cho `status`). Chỉ là gợi ý UI; native vẫn chặn ghi.

### 4.5 Giá trị (FR-06)

`dataType` và `value` tính từ **schema native** của (project, type), không đoán theo tên: `string|formattable|integer|float|duration|date|datetime|bool|link|linkList|unknown`. Dạng `value`: `{raw, display}`; `formattable`: `{format, raw, html}` (`html` do OpenProject sanitize); `link`: `{raw: id, display: name}`; `linkList`: `{raw: [ids], display: [names]}`. `display` dịch theo locale và định dạng ngày/số của user. `unknown` ⇒ `{raw: null, display: null}`, `editable: false`.

### 4.6 Ánh xạ snake_case (F03) → camelCase (F04)

`source`, `reason` giữ nguyên chuỗi; `state_source` bỏ; `state.default_value` → `state.defaultValue`, `read_only` → `readOnly`; section `id` → String; diagnostics theo §4.3.

### 4.7 Counts, parent, lockVersion (FR-10, FR-11)

Chỉ tính khi WP visible; mỗi count một truy vấn nhóm/đếm duy nhất:

| count | quy tắc |
|---|---|
| `comments` | số journal có `notes` không rỗng trong `journals.internal_visible.meeting_cause_visible` |
| `children` | `WorkPackage.visible(user).where(parent_id: id).count` |
| `relations` | `Relation.visible(user)` của WP, **không** gồm parent/children |
| `attachments` | số attachment của WP; **vắng khoá** nếu `project.deactivate_work_package_attachments?` |
| `watchers` | **vắng khoá** nếu user không có `view_work_package_watchers` ở project |

Không có `counts.activities`. `parent`: `{id, identifier, subject}` chỉ khi `WorkPackage.visible(user)` cho phép; ngược lại `null` (không `title` trong link). `lockVersion` = `lock_version` của đúng bản WP đã dùng dựng payload (một lần load).

## 5. Hợp đồng `GET /api/v3/work_packages/{id}/issue_view/activities`

### 5.1 Tham số và envelope (FR-18)

`offset` (trang 1-based; `<1`/không số ⇒ 1), `pageSize` (mặc định 20; `-1` hoặc `> min(100, Setting.apiv3_max_page_size)` ⇒ kẹp; `0`/không số ⇒ trang rỗng, `total` đúng; âm khác −1 ⇒ 400), `sortBy=[["timestamp","asc"]]` (khoá duy nhất `timestamp`, mặc định `asc`), `filters=[{"type":{"operator":"=","values":["COMMENT"]}}]` (chỉ lọc `type`; `type` ngoài tập đóng ⇒ 400). Envelope collection API v3 (`total, count, pageSize, offset, _embedded.elements`). **Phân trang theo journal**: `pageSize` đếm journal, `total` = số journal hiển thị; mỗi journal sinh 0..N event trong cùng trang. **Lọc `type`** (Q-I): journal được giữ nếu có ≥1 event khớp, và chỉ trả các event khớp của journal đó; `total` đếm journal được giữ. Vì loại event chỉ biết sau khi tách, lọc thực hiện trên tập journal đã nạp (đã bị `internal_visible`); spec implement chọn nạp tối đa một trang rồi lọc, hoặc lọc SQL cho `COMMENT` (`notes <> ''`) và ghi lựa chọn trong plan.

Tham số sai (tên/toán tử/giá trị, JSON hỏng, `pageSize` âm ≠ −1) ⇒ 400 `InvalidQuery`; endpoint tự `rescue JSON::ParserError` và tự validate `pageSize`.

### 5.2 Nguồn và visibility (FR-14, FR-17, FR-19)

* Nguồn: `work_package.journals.internal_visible.meeting_cause_visible.includes(<như E3>)` rồi áp `order`/phân trang; **không** truy vấn thẳng bảng journals, không parser song song.
* Journal nội bộ mà user không xem được ⇒ toàn bộ event của nó vắng, không tính vào `total`/`counts.comments`.
* Preload actor (kèm avatar), details; test đếm truy vấn không tăng theo số journal trong trang.

### 5.3 Tách event và mapping (FR-15, FR-16)

Cho mỗi journal: (1) nếu `notes` không rỗng ⇒ event `COMMENT` id `"<journalId>:comment"`; (2) duyệt `journal.details` theo thứ tự chèn, bỏ detail mà `render_detail` trả `nil`/`""`; mỗi detail còn lại ⇒ một event id `"<journalId>:<n>"` (`n` 0-based **sau lọc**). Journal sắp theo `(created_at, id)`. Journal rỗng ⇒ không event.

| Điều kiện detail | `type` | Trường riêng |
|---|---|---|
| `notes` | `COMMENT` | `comment: {id, body: {format, raw, html}, internal, createdAt, updatedAt}`; link `update` (native `PATCH /activities/{id}`) chỉ khi native cho phép |
| `attachments_<id>`, old nil | `ATTACHMENT_ADDED` | `attachment: {id, fileName}`; link chỉ khi attachment còn tồn tại |
| `attachments_<id>`, new nil | `ATTACHMENT_REMOVED` | `attachment: {id, fileName}` |
| `cause`, `file_links_*`, `custom_comment*`, `project_phase*`, `agenda_items*`, `participants*` | `OTHER` | `description: {raw, html}`, `causeType` nếu có |
| mọi key khác (`subject`, `*_id`, ngày, `description`, `target_versions`, `custom_fields_N`…) | `FIELD_CHANGED` | `field` (key), `raw: {from, to}` (giá trị thô trong details), `description: {raw, html}` (`render_detail` với `html: false`/`true`) |

Chung: `_type: "IssueViewEvent"`, `id`, `journalId`, `type`, `actor {id, name, _links.self, _links.avatar}`, `timestamp`. Tập `type` **đóng**; client gặp giá trị lạ ⇒ render chung. `description` được render với `activity_page: "work_packages/<id>"` như `activity_property_formatters.rb`. Không có `from/to.display` riêng (E5, Q-H).

## 6. Bảo mật, hiệu năng, an toàn

* **Authz (FR-25):** thừa kế native (E1/E2). Ma trận test: anonymous (public + Anonymous role có/không quyền; `login_required` bật), non-member, viewer, member, admin, project archived, WP project khác. Không bao giờ 403.
* **Không ghi (FR-24):** test khẳng định `issue_view*` chỉ có route `GET`.
* **Rò rỉ:** comment nội bộ + count; journal meeting ẩn; WP đích/parent/children không thấy; field không xem được; `diagnostics` (admin-only); `display` đối tượng không xem được qua formatter native (placeholder).
* **Cache (FR-27):** `Cache-Control: private, no-cache`, `Vary: Authorization, Cookie, Accept-Language`; không ETag. Cache chỉ `RequestStore`.
* **Hiệu năng:** số truy vấn `issue_view` với 5 field **bằng** 50 field (assert bằng nhau); trần tuyệt đối đo từ baseline khi implement rồi cố định trong test; preload custom field values; quyền tra một lần; counts mỗi loại một truy vấn. Activity: số truy vấn không tăng theo số journal trong trang.
* **Fail-open (FR-13):** F02/F03/builder lỗi ⇒ log + `Rails.error.report(handled: true)` + `native`/`reason:"error"`, 200. Chỉ lỗi nếu không đọc được WP. Endpoint activity không fail-open (500 `InternalServerError`).
* **XSS:** `html` do OpenProject sanitize; `display` là chuỗi thuần; không log nội dung người dùng.
* **i18n (FR-26):** `config/locales/en.yml` cho nhãn/lỗi (`issue_view.*`); không hard-code. Không "jira" trong bất kỳ tên nào.
* **Feature flag (Q-G):** module có thể tắt qua `Setting`/env theo cách F03 làm rollout (agent đọc F03 §14 "Rollout / feature flag"); tắt ⇒ route 404; mặc định theo F03.

## 7. Bảng lỗi (mọi endpoint)

| Tình huống | HTTP | Định danh |
|---|---|---|
| OK | 200 | — |
| `login_required` bật, chưa đăng nhập | 401 | `Unauthenticated` |
| WP/project không thấy, thiếu quyền, archived, id sai | 404 | `NotFound` |
| `filters`/`sortBy`/`type` sai, JSON hỏng, `pageSize` âm ≠ −1 | 400 | `InvalidQuery` |
| Lỗi nội bộ endpoint activity | 500 | `InternalServerError` |

## 8. Điểm tựa core cho boot guard

`WorkPackages::BaseContract#assignable_statuses`, `WorkPackage#display_id`, `WorkPackage.visible`, `Relation.visible`, `Journal#details`/`JournalFormatter#render_detail`, `work_package.journals.internal_visible`, `API::V3::WorkPackages::WorkPackagesAPI`, `OpenProject::Plugins::ActsAsOpEngine#add_api_endpoint`, `API::Decorators::OffsetPaginatedCollection`. Thiếu ⇒ `assert_core_dependencies!` raise sớm với thông điệp rõ.

## 9. OpenAPI

`docs/api/apiv3/paths/work_package_issue_view.yml`, `…_activities.yml`; `docs/api/apiv3/components/schemas/issue_view_model.yml`, `issue_view_event_model.yml`, `issue_view_event_collection_model.yml`. Mỗi endpoint cập nhật trong lát phát hành nó. `add_api_path :work_package_issue_view`, `:work_package_issue_view_activities` (theo mẫu `add_api_path` của screens).

## 10. Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Sinh `permissions` bằng representer đầy đủ ⇒ chậm/N+1 | Dùng contract/link gate rẻ; test query-count; ghi chọn lựa trong plan |
| `render_detail` N+1 (tra object) | Preload `:data, :customizable_journals, :attachable_journals`; đo; giới hạn pageSize ≤ 100 |
| `JSON::ParserError` ⇒ 500 nếu quên rescue | Test bắt buộc (§12 #18) |
| Lệch `editable` so với native | Parity test với `POST /work_packages/{id}/form` |
| Phụ thuộc F02/F03 đổi shape | Boot guard + contract test nhỏ cho `ResolvedScreen` |
| Module mới đăng ký `Gemfile.modules` | Theo mẫu screens; kiểm CI |

## 11. Cắt lát

1. **Slice 1:** module skeleton (gemspec, engine, `Gemfile.modules`, locale), `Builder`, `Permissions`, `Counts`, endpoint `issue_view`, `add_api_path`, OpenAPI, test unit/request/authz/leak.
2. **Slice 2:** `ActivityNormalizer`, phân trang/filter/sort, endpoint `activities`, OpenAPI, test.
3. **Slice 3:** hardening — fail-open, query-count, contract test, feature flag, route-no-write test, rubocop.

## 12. Kiểm thử & truy vết

Cấu trúc: `modules/issue_view/spec/{services,requests/api/v3,support,factories}/…`. Request spec: `issue_view_api_spec.rb`, `issue_view_activities_api_spec.rb`, `issue_view_authz_spec.rb`, `issue_view_contract_spec.rb`.

| # | Kịch bản | FR |
|---|---|---|
| 1 | Screen `view` F03 ⇒ sections đúng thứ tự/`width`; field F02 hidden vắng | 04 |
| 2 | Project không scheme ⇒ `native`, sections từ `_attributeGroups`, `reason: no_scheme` | 05 |
| 3 | F03 lỗi giả lập ⇒ 200 `native`, `reason: error`, `Rails.error.report` được gọi; F02 vắng ⇒ `state: null`; F03 vắng ⇒ `module_disabled` | 13 |
| 4 | Assignee `null` ⇒ `header.assignee: null` | 03 |
| 5 | semantic ⇒ `PROJ-123`; classic ⇒ `"12345"`; path nhận cả hai; WP chuyển project ⇒ key mới | 02 |
| 6 | Mỗi `dataType`; kiểu lạ ⇒ `unknown`; ngày/số theo user | 06 |
| 7 | Custom field tắt/không xem ⇒ vắng | 07 |
| 8 | Ma trận 9 quyền × (viewer, member, admin); link vắng khi `false`; PATCH native vẫn bị chặn dù `permissions` bị giả | 08, 25 |
| 9 | `readOnly` F02, WP khoá, thứ tự ưu tiên lý do, parity `/form` | 09 |
| 10 | Status: có/không đích khả dụng ⇒ `transition`; status mồ côi | 08, 21 |
| 11 | Counts: thiếu `view_internal_comments`; relation tới WP không thấy; children không thấy; attachments khi project tắt; watchers vắng khoá | 10 |
| 12 | `lockVersion` khớp; PATCH native cũ ⇒ 409 | 11, 21 |
| 13 | `diagnostics` chỉ admin, 2 khoá camelCase | 12 |
| 14 | Parent không thấy ⇒ `null` | parent |
| 15 | Journal `notes` + 2 detail ⇒ 3 event, id `:comment`,`:0`,`:1`; detail rỗng bị bỏ ⇒ `n` liên tục | 15 |
| 16 | Mapping §5.3: attachment add/remove, cause ⇒ `OTHER`, custom field, description | 16 |
| 17 | Journal nội bộ + user thiếu quyền ⇒ biến mất hoàn toàn; meeting cause ẩn | 14, 17 |
| 18 | `pageSize=1000` ⇒ kẹp; `-5` ⇒ 400; `0` ⇒ rỗng+total; `offset=0/abc` ⇒ trang 1; `filters=abc`/`sortBy=abc` ⇒ 400 (không 500); lọc `type=COMMENT`; phân trang theo journal | 18 |
| 19 | Sửa comment bằng native PATCH; không có DELETE | 19 |
| 20 | Query count 5 vs 50 field bằng nhau; activity không N+1 | 20 |
| 21 | Route chỉ `GET`; không có `issue_view/relations|transitions` | 24 |
| 22 | Ma trận authz (§6) kể cả archived, anonymous | 25 |
| 23 | `Cache-Control`/`Vary`; không ETag | 27 |
| 24 | i18n; không "jira" (grep test) | 26 |
| 25 | Feature flag tắt ⇒ 404 | Q-G |

(FR-xx tham chiếu đánh số trong `docs/ideas/idea-04.md`.)

## 13. Acceptance

Hoàn thành khi: 2 endpoint đúng hợp đồng §4–§5; mọi kịch bản §12 xanh; OpenAPI + contract test; không route ghi, không bảng/migration, không sửa core; ma trận authz + test rò rỉ; không N+1; i18n, không "jira"; rubocop sạch; module tắt ⇒ 404. Không làm: workflow engine, automation, advanced linking, dashboard, search, bulk edit, relations/transitions riêng, frontend.

## 14. Quyết định đã chọn mặc định

| ID | Quyết định |
|---|---|
| Q-A | Fallback layout `view`: native, header luôn có |
| Q-C | Không phơi F03 `transition` |
| Q-D | Path nhận id số hoặc semantic (E1/E9) |
| Q-E | Không endpoint đa WP |
| Q-F | Anonymous theo native (E2) |
| Q-G | Feature flag, tắt ⇒ 404; mặc định theo cơ chế F03 |
| Q-H | Không resolve tên cho `raw.from/to`; dùng `description` |
| Q-I | Phân trang theo journal; lọc `type` giữ journal có ≥1 event khớp và chỉ trả event khớp (§5.1) |
