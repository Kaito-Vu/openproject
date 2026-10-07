# Issue View Implementation Plan

> **Dành cho agent thực thi:** làm tuần tự từng task; mỗi step dùng checkbox. Viết test trước, chạy thấy fail đúng thông báo dự kiến, rồi mới viết code. Mỗi task có **DoD** (Definition of Done) và **Files**. Không gộp task, không bỏ qua cổng dừng.

**Goal:** Module `modules/issue_view` cung cấp hai endpoint API v3 **chỉ đọc** — `GET /api/v3/work_packages/{id}/issue_view` (header, layout F03/native, giá trị + trạng thái field, quyền, counts) và `…/issue_view/activities` (timeline chuẩn hoá, phân trang) — để frontend riêng render trang chi tiết issue.

**Architecture:** Rails engine theo mẫu `modules/screens`. Không bảng/migration/route ghi/ETag. Mount bằng `add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id` để thừa kế `WorkPackage.visible` + 404. F02/F03 là phụ thuộc mềm, fail-open.

**Tech Stack:** Rails 8.1, RSpec, Grape API v3.

**Spec (nguồn sự thật):** [../specs/2026-10-06-issue-view-design.md](../specs/2026-10-06-issue-view-design.md) · **Idea:** [../../ideas/idea-04.md](../../ideas/idea-04.md) · **Checklist:** [2026-10-06-issue-view-checklist.md](2026-10-06-issue-view-checklist.md)

## Quy tắc xác minh (bắt buộc)

- Môi trường tác giả (Windows) không có Ruby/Postgres/Docker ⇒ không chạy được RSpec/rubocop. Step "chạy test" thực hiện trên máy dev (`bin/compose-dev rspec …`).
- Mỗi task kết thúc bằng khối **Verification** trong checklist: lệnh, exit status, số pass/fail dán nguyên văn. Chưa chạy ⇒ ghi `UNVERIFIED (not run)`, commit mang `[unverified]`; **không** viết "pass".
- Mỗi lát (slice) một nhánh/PR draft từ nền xanh; lát lỗi ⇒ `git revert` các commit của lát (không có migration để rollback).
- Không `--no-verify`. Hook: `bundle exec lefthook install` (Task 0).

## Global Constraints

- Không sửa Ruby core, không `prepend`, không bảng/migration, không route ghi (chỉ `GET`), không ETag, không `Rails.cache`.
- Không "jira" trong tên bảng/class/route/permission/menu/i18n/API/file.
- Không `authorize_logged_in`, không `authorize` riêng cho quyền xem WP; kiểm tra bổ sung phải `raise ::API::Errors::NotFound`.
- Không 403 từ module này.
- Trong engine/model/lib luôn viết `::IssueView::…` (tránh nhầm `OpenProject::IssueView`); namespace Ruby `IssueView` cho service, `API::V3::IssueView` cho Grape/representer.
- Giới hạn: activities `pageSize` ≤ `min(100, Setting.apiv3_max_page_size)`.
- Fail-open (chỉ `issue_view`): `Rails.error.report(e, handled: true, context: {…})` + `OpenProject.logger.error` + layout native `reason: "error"`. Activities **không** fail-open.
- i18n: mọi nhãn/lỗi qua `modules/issue_view/config/locales/en.yml` (`issue_view.*`); không hard-code.
- Mặc định **không comment** (CLAUDE.md); chỉ header copyright + ghi chú ràng buộc không hiển nhiên.
- Header copyright mọi `.rb`/`.rake` (copy từ `modules/screens/lib/open_project/screens/engine.rb`).
- Commit: dòng đầu < 72 ký tự, thân mô tả, tham chiếu work package (hỏi người dùng nếu chưa có), trailer attribution của phiên.
- Quality gate mỗi task: `bundle exec rubocop <files>`.
- Helper dùng chung (Task 2): `spec/support/query_counter.rb` (đếm `sql.active_record` trong `ActiveSupport::Notifications.subscribed`, bỏ `SCHEMA/TRANSACTION/SAVEPOINT`).

## File Structure

```text
modules/issue_view/
  openproject-issue_view.gemspec
  lib/openproject-issue_view.rb                   # require "open_project/issue_view"
  lib/open_project/issue_view.rb                  # assert_core_dependencies!
  lib/open_project/issue_view/engine.rb           # register, add_api_endpoint, add_api_path
  lib/api/v3/issue_view/{issue_view_api,issue_view_representer,activities_params,activity_event_representer,activity_collection_representer}.rb
  app/services/issue_view/{builder,layout,values,permissions,counts,activity_normalizer,fail_open}.rb
  config/locales/en.yml
  spec/{services/issue_view,requests/api/v3,lib/open_project/issue_view,support,factories}/…
Gemfile.modules                                   # + 1 dòng (căn cột như dòng openproject-screens)
docs/api/apiv3/{paths,components/schemas}/…       # theo lát phát hành; đăng ký trong openapi-spec.yml
```

---

# Lát 1 — `issue_view`

## Task 0 — Pre-flight + cổng dừng

**Files:** `docs/superpowers/plans/2026-10-06-issue-view-preflight.md` (kết quả), không code.

- [ ] Đọc spec F04 §1 (E1–E13) và `docs/superpowers/specs/2026-10-05-screens-design.md` §14 mục "Rollout / feature flag" (để biết cơ chế flag F03 dùng cho Q-G).
- [ ] `rails runner` xác nhận tồn tại: `WorkPackages::BaseContract#assignable_statuses`, `WorkPackage#display_id`, `Relation.visible`, `Journal#details`, `JournalFormatter#render_detail`, `work_package.journals.internal_visible`, `API::Decorators::OffsetPaginatedCollection`, `OpenProject::Plugins::ActsAsOpEngine#add_api_endpoint`, `::Screens::Resolver.for`. Ghi từng cái PASS/FAIL (hoặc "theo code inspection" + file:line nếu không chạy được).
- [ ] Quyết định (ghi vào preflight): (a) cách `Permissions` lấy link/contract **không N+1**: (i) dựng `WorkPackageRepresenter` rồi đọc `_links` hay (ii) gọi contract/`allowed_in_work_package?` một lần preload; chọn (ii) nếu (i) quá nặng khi đo; (b) cơ chế feature flag Q-G theo F03; (c) cách lấy schema native (project,type) rẻ nhất (`API::V3::WorkPackages::Schema::SpecificWorkPackageSchema` / `TypedWorkPackageSchema`).
- [ ] **Cổng dừng:** mục nào FAIL (core khác mô tả) ⇒ dừng, ghi chênh lệch vào preflight, đề xuất chỉnh spec; **không** tự suy diễn.

**DoD:** file preflight có bảng điểm tựa + 3 quyết định; không FAIL chưa xử lý.

## Task 1 — Skeleton module + mount rỗng

**Files:** `openproject-issue_view.gemspec`, `lib/openproject-issue_view.rb`, `lib/open_project/issue_view.rb`, `lib/open_project/issue_view/engine.rb`, `lib/api/v3/issue_view/issue_view_api.rb`, `config/locales/en.yml`, `Gemfile.modules`, `spec/lib/open_project/issue_view/engine_spec.rb`.

- [ ] Test trước (`engine_spec.rb`): (1) `OpenProject::IssueView.assert_core_dependencies!` không raise; (2) khi một điểm tựa bị stub thiếu ⇒ raise với thông điệp nêu tên điểm tựa; (3) `API::V3::WorkPackages::WorkPackagesAPI` có route `GET …/issue_view`.
- [ ] Tạo gemspec/engine theo `modules/screens` (copy cấu trúc, đổi tên; `bundled: true`, `engine_name :openproject_issue_view`; `config.to_prepare { OpenProject::IssueView.assert_core_dependencies! }`).
- [ ] `add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id do mount ::API::V3::IssueView::IssueViewAPI end`; `IssueViewAPI < ::API::OpenProjectAPI`, `get :issue_view` trả `{ _type: "IssueView" }` tạm.
- [ ] `add_api_path :work_package_issue_view` (`"#{work_package(id)}/issue_view"`) và `:work_package_issue_view_activities`.
- [ ] Thêm dòng vào `Gemfile.modules` (căn cột).
- [ ] Chạy engine_spec ⇒ xanh; rubocop.

**DoD:** module nạp được; route tồn tại; boot guard test xanh.

## Task 2 — Support: query counter, factories, authz helper

**Files:** `spec/support/query_counter.rb`, `spec/support/issue_view_helpers.rb`, `spec/factories/…` (chỉ nếu thiếu).

- [ ] `query_counter.rb` như Global Constraints.
- [ ] Helper dựng WP với N custom field/journal/relation/attachment/watcher; helper `as_user(role)` cho ma trận (anonymous, non-member, viewer, member, admin).
- [ ] Spec nhỏ cho query counter (đếm đúng, bỏ SCHEMA).

**DoD:** helper dùng được từ các spec sau; spec xanh.

## Task 3 — `IssueView::Permissions`

**Files:** `app/services/issue_view/permissions.rb`, `spec/services/issue_view/permissions_spec.rb`.

- [ ] Test trước: bảng 9 khoá × (viewer, member sửa được, admin, project archived/WP locked); `transition` đúng khi có ≥1 status khác hiện tại và `edit`; `logTime` `false` khi module costs tắt; module trả hash đủ 9 khoá boolean.
- [ ] Triển khai theo quyết định Task 0(a); nguồn duy nhất của quyền (không rải `allowed_to?` nơi khác).
- [ ] Trả thêm `links`-gate: `permissions.links` nội bộ (symbol set) để Builder biết link nào được phát.
- [ ] Query-count: một lần tra quyền cho cả 9 khoá (assert không tăng khi gọi lại trong cùng request).

**DoD:** spec xanh; không gọi `allowed_to?` ngoài file này (grep trong module).

## Task 4 — `IssueView::Counts`

**Files:** `app/services/issue_view/counts.rb`, spec.

- [ ] Test trước: (1) `comments` = journal có `notes` trong `internal_visible.meeting_cause_visible`; user thiếu `view_internal_comments` ⇒ không tính comment nội bộ; (2) `children` chỉ con visible; (3) `relations` chỉ relation có cả hai đầu visible, không gồm parent/children; (4) `attachments` vắng khoá khi `project.deactivate_work_package_attachments?`; (5) `watchers` vắng khoá khi thiếu `view_work_package_watchers`; (6) không có `activities`.
- [ ] Triển khai: mỗi count một truy vấn (`count`), dùng `WorkPackage.visible(user)`, `Relation.visible(user)`; không N+1.
- [ ] Parent: `IssueView::Counts.parent(work_package, user)` ⇒ `{id, identifier, subject}` hoặc `nil` (qua `WorkPackage.visible(user)`).

**DoD:** spec xanh gồm 3 test rò rỉ (comment nội bộ, relation/children không thấy, parent không thấy).

## Task 5 — `IssueView::Values` (dataType, value, editable)

**Files:** `app/services/issue_view/values.rb`, spec.

- [ ] Test trước: mỗi `dataType` (string, formattable, integer/float/duration, date/datetime, bool, link, linkList, unknown) ⇒ `value` đúng dạng; `display` theo locale/định dạng user; `unknown` ⇒ `{raw: nil, display: nil}`, `editable:false`; field không khả dụng/không xem được bị loại.
- [ ] `editable` + `editableReason`: `edit ∧ writable ∧ ¬readOnly`; `status` ⇔ `transition`; thứ tự ưu tiên `locked > no_permission > not_writable > read_only > workflow`; `editable ⇒ reason nil`.
- [ ] Nguồn kiểu/`writable`: schema native (Task 0(c)); **không** đoán theo tên.
- [ ] Parity spec: với cùng user, `editable` khớp `writable` trong `POST /api/v3/work_packages/{id}/form` schema.

**DoD:** spec xanh gồm parity; không `to_s` đối tượng lạ.

## Task 6 — `IssueView::Layout` (F03/native/fail-open/diagnostics)

**Files:** `app/services/issue_view/{layout,fail_open}.rb`, spec.

- [ ] Test trước: (1) `source:"screen"` ⇒ sections/fields theo `position`, `width`, `state`, section `id` String, `reason: nil`; (2) project không scheme ⇒ `native`, sections từ `_attributeGroups` (bỏ group query), `width:"full"`, `state:nil`, `reason:"no_scheme"`; (3) F03 raise ⇒ `native`, `reason:"error"`, `Rails.error.report` được gọi, 200; (4) F03 không nạp (`hide_const`) ⇒ `module_disabled`; (5) F02 vắng ⇒ `state: nil`; (6) `diagnostics`: admin có `unavailable`/`hiddenButPlaced` camelCase, non-admin **không có khoá**; không lộ `not_visible/required_not_placed/skipped/empty_create_screen/error`.
- [ ] `fail_open` theo mẫu `Screens::Resolver#fail_open` (log + `Rails.error.report`).
- [ ] Triển khai thuật toán spec §4.3 (6 bước) + ánh xạ snake→camel §4.6.

**DoD:** spec xanh; không phụ thuộc cứng vào `::Screens`/`::FieldRules` (dùng `defined?`).

## Task 7 — `Builder` + representer + endpoint `issue_view`

**Files:** `app/services/issue_view/builder.rb`, `lib/api/v3/issue_view/{issue_view_representer,issue_view_api}.rb`, `spec/requests/api/v3/issue_view_api_spec.rb`, `issue_view_authz_spec.rb`.

- [ ] Test trước (request): payload gồm `_type, id, identifier, subject, source, reason, header(5 khoá), sections, permissions(9), counts, parent, lockVersion, _links`; `identifier` semantic/classic và path nhận cả hai; WP chuyển project ⇒ key mới; header `assignee:null`; link `updateImmediately/addComment/…` chỉ khi quyền true; `allowedStatuses` là link form POST.
- [ ] Test authz (ma trận spec §6): anonymous (public + role Anonymous có/không quyền; `login_required` on ⇒ 401 `Unauthenticated`), non-member, viewer, member, admin, project archived, WP project khác ⇒ 404 `NotFound`; **không** 403.
- [ ] Headers: `Cache-Control: private, no-cache`, `Vary: Authorization, Cookie, Accept-Language`; không `ETag`.
- [ ] `Builder.call(work_package, user)` ghép Layout + Values + Permissions + Counts; `lockVersion` từ cùng bản WP (một lần load).
- [ ] Representer HAL; `IssueViewAPI` dùng reader `work_package`, không `authorize`.
- [ ] Query-count spec: 5 field vs 50 field ⇒ cùng số truy vấn (assert bằng nhau).

**DoD:** request spec + authz + query-count xanh; payload khớp ví dụ idea §6.

## Task 8 — OpenAPI + contract test (`issue_view`)

**Files:** `docs/api/apiv3/paths/work_package_issue_view.yml`, `docs/api/apiv3/components/schemas/issue_view_model.yml`, đăng ký trong `docs/api/apiv3/openapi-spec.yml`, `spec/requests/api/v3/issue_view_contract_spec.rb`.

- [ ] Viết path + schema (đủ trường, enum `source/reason/dataType/editableReason`, 9 quyền, `counts` khoá tuỳ chọn, `diagnostics` tuỳ chọn); lỗi 401/404.
- [ ] Contract spec: response thật validate theo schema (theo cơ chế contract spec sẵn có của repo cho API v3; nếu không có, so khoá/kiểu bằng JSON schema nạp từ yml).
- [ ] Lint OpenAPI (`npm run lint:api` nếu có; ghi lệnh thực tế).

**DoD:** spec xanh; lint sạch hoặc `UNVERIFIED`.

---

# Lát 2 — `issue_view/activities`

## Task 9 — `IssueView::ActivityNormalizer`

**Files:** `app/services/issue_view/activity_normalizer.rb`, spec.

- [ ] Test trước (spec §5.3): journal `notes` + 2 detail ⇒ 3 event, id `"<jid>:comment"`, `"<jid>:0"`, `"<jid>:1"`; detail mà `render_detail` trả `nil`/`""` bị bỏ và `n` liên tục; `attachments_N` old nil ⇒ `ATTACHMENT_ADDED`, new nil ⇒ `ATTACHMENT_REMOVED` (id từ hậu tố key); `cause`, `file_links_*`, `custom_comment*`, `project_phase*`, `agenda_items*`, `participants*` ⇒ `OTHER` (+`causeType`); `custom_fields_N`, `description`, `*_id`, ngày ⇒ `FIELD_CHANGED` với `field`, `raw:{from,to}`, `description:{raw,html}`; journal rỗng ⇒ không event; thứ tự `(created_at, id)` rồi thứ tự details.
- [ ] `description.raw` = `render_detail(html: false)`, `html` = `render_detail(html: true, only_path: true, activity_page: "work_packages/<id>")`.
- [ ] Triển khai chỉ nhận **scope đã lọc** (`internal_visible.meeting_cause_visible`), không tự query bảng journals.
- [ ] Journal nội bộ user không xem được không bao giờ tới normalizer (test ở Task 12).

**DoD:** spec xanh cho từng dòng mapping.

## Task 10 — Tham số: phân trang, sort, filter

**Files:** `lib/api/v3/issue_view/activities_params.rb`, spec.

- [ ] Test trước: `offset` `<1`/`abc` ⇒ 1; `pageSize` mặc định 20, `-1` hoặc `>max` ⇒ `min(100, apiv3_max_page_size)`, `0` ⇒ trang rỗng (total đúng), `abc` ⇒ rỗng, `-5` ⇒ lỗi 400 `InvalidQuery`; `sortBy` chỉ `timestamp` (`asc` mặc định, `desc`), khoá khác ⇒ 400; `filters` chỉ `type` toán tử `=` với giá trị trong tập đóng; `filters=abc`/`sortBy=abc` (JSON hỏng) ⇒ **400** (rescue `JSON::ParserError`, không 500); cấu trúc sai (object thay array) ⇒ 400.
- [ ] Trả struct `{page, per_page, sort, types}`; lỗi raise `::API::Errors::InvalidQuery`.

**DoD:** spec xanh gồm các ca JSON hỏng.

## Task 11 — Representer + endpoint `activities`

**Files:** `lib/api/v3/issue_view/{activity_event_representer,activity_collection_representer}.rb`, mở rộng `issue_view_api.rb`, `spec/requests/api/v3/issue_view_activities_api_spec.rb`.

- [ ] Test trước: envelope `total,count,pageSize,offset,_embedded.elements`; **phân trang theo journal** (`pageSize` đếm journal, `total` = số journal hiển thị); lọc `type=COMMENT` giữ journal có ≥1 event khớp và chỉ trả event khớp (Q-I); sort asc/desc; event có `_type:"IssueViewEvent"`, `id`, `journalId`, `type`, `actor{id,name,_links.self,_links.avatar}`, `timestamp`; `COMMENT` có `comment{id,body{format,raw,html},internal,createdAt,updatedAt}` và link `update` chỉ khi native cho phép.
- [ ] Nguồn: `work_package.journals.internal_visible.meeting_cause_visible.includes(:data, :customizable_journals, :attachable_journals, :storable_journals, :bcf_comment, :user)` + `OffsetPaginatedCollection`; không parser song song.
- [ ] Lọc `type`: chọn (nạp một trang rồi lọc) hoặc SQL cho `COMMENT` (`notes <> ''`); ghi lựa chọn vào preflight/plan; test cả hai nhánh nếu có hai.
- [ ] Lỗi endpoint ⇒ 500 `InternalServerError` (không fail-open).

**DoD:** request spec xanh.

## Task 12 — Leak, authz, query-count cho `activities` + OpenAPI

**Files:** `spec/requests/api/v3/issue_view_activities_leak_spec.rb`, `docs/api/apiv3/paths/work_package_issue_view_activities.yml`, `components/schemas/issue_view_event_model.yml`, `issue_view_event_collection_model.yml`, đăng ký, contract spec.

- [ ] Test rò rỉ: journal nội bộ + user thiếu `view_internal_comments` (hoặc project chưa bật `enabled_internal_comments`/thiếu token EE) ⇒ **không** event nào của journal đó (kể cả detail), `total` và `counts.comments` không tính; journal có cause meeting ẩn ⇒ vắng; detail người/đối tượng không xem được ⇒ placeholder native, không lộ tên (dựa formatter).
- [ ] Ma trận authz giống Task 7 cho endpoint này (404/401).
- [ ] Query-count: số truy vấn không tăng khi trang có 5 vs 25 journal (preload).
- [ ] Sửa comment: `PATCH /api/v3/activities/{id}` native hoạt động; không có route `DELETE` ở module (kiểm ở Task 14).
- [ ] OpenAPI + contract spec cho activities.

**DoD:** spec xanh; OpenAPI đủ.

---

# Lát 3 — Hardening

## Task 13 — Feature flag (Q-G)

**Files:** engine/`IssueViewAPI`, `config/locales/en.yml`, spec.

- [ ] Triển khai theo cơ chế F03 (Task 0(b)): flag tắt ⇒ cả hai route trả 404 `NotFound`.
- [ ] Test: flag tắt ⇒ 404 mọi endpoint; flag bật ⇒ như Task 7/11.

**DoD:** spec xanh; mặc định flag ghi trong preflight.

## Task 14 — Bất biến toàn module

**Files:** `spec/lib/open_project/issue_view/invariants_spec.rb`.

- [ ] Route test: mọi route của module chỉ `GET` (không POST/PUT/PATCH/DELETE); không có `issue_view/relations|transitions`.
- [ ] Grep test: không "jira" (case-insensitive) trong `modules/issue_view/**` và đường dẫn; không `authorize_logged_in`, không `allowed_to?` ngoài `permissions.rb`; không `Rails.cache`/`ETag`.
- [ ] i18n: mọi khoá dùng trong code có trong `en.yml`.
- [ ] Header copyright: `rake copyright:update` kiểm (hoặc ghi lệnh thực tế).

**DoD:** invariants_spec xanh.

## Task 15 — Kiểm toàn bộ + bàn giao

- [ ] `bundle exec rspec modules/issue_view` (toàn module); `bundle exec rubocop modules/issue_view`; `rake copyright:*` nếu có; OpenAPI lint.
- [ ] Rà acceptance (spec §13) từng dòng; rà bảng truy vết spec §12 (25 kịch bản ⇒ spec tương ứng).
- [ ] Cập nhật checklist Verification; mở PR draft (mỗi lát một PR); báo rõ mục UNVERIFIED.

**DoD:** checklist đầy đủ; mọi UNVERIFIED được liệt kê.
