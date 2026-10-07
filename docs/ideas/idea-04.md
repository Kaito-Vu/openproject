# Feature 04 — Issue View (lớp trình bày Work Package)

> **Loại tài liệu:** idea brief — đầu vào cho AI coding agent viết **spec → plan → implementation**.
> **Phụ thuộc:** F01 (`modules/type_schemes`), F02 (`modules/field_rules`), F03 (`modules/screens`). F02/F03 là **phụ thuộc mềm** (FR-13).
> **Module đề xuất:** `modules/issue_view`.
> **Phạm vi:** **backend** (API v3 + test + OpenAPI). Frontend Vue/React riêng nằm **ngoài repo** (§12).
> **Trạng thái review:** đã qua hội đồng 3 góc nhìn + 1 vòng sửa (Phụ lục A).

## 0. Cách dùng tài liệu này (dành cho AI agent)

1. Đọc toàn bộ, sau đó đọc `docs/superpowers/specs/2026-10-05-screens-design.md` (§4–§7: mã lỗi, `state`, `diagnostics`, ánh xạ lỗi API v3) và `2026-10-03-field-rules-design.md`.
2. **Kiểm chứng giả định ở §3 trong code thật** trước khi viết spec. Cột "Trạng thái" cho biết mục nào đã xác minh khi viết brief (kèm vị trí) và mục nào còn mở. Code khác mô tả ⇒ ghi chênh lệch vào spec, không tự suy diễn.
3. Viết spec vào `docs/superpowers/specs/<ngày>-issue-view-design.md` (cùng format spec F03: bảng đối chiếu code, quyết định, rủi ro), rồi plan chia task nhỏ có tiêu chí hoàn thành + test, rồi mới implement.
4. **[Q-x]** có mặc định; dùng mặc định nếu chủ sản phẩm chưa trả lời và ghi vào spec.
5. **MUST / MUST NOT** là ràng buộc cứng; **SHOULD** là mong muốn. Mỗi FR có ≥1 test: bảng truy vết FR → kịch bản ở §17.
6. Jira chỉ để so sánh khái niệm. **MUST NOT** dùng "jira" trong bảng, class, route, permission, menu, i18n, API, tên file.

## 1. Ý tưởng cốt lõi

OpenProject đã có trang chi tiết Work Package, Activity, Relations, Watchers, Attachments, Hierarchy và API v3. Feature này **không** clone chúng và **không** tạo model "Issue".

> **Issue = Work Package native.** F04 là **Issue View Presentation Layer**: API **chỉ đọc**, gom và chuẩn hoá dữ liệu để frontend riêng render trang chi tiết kiểu Jira mà không phải biết nhiều chi tiết API OpenProject.

Giá trị thực — chỉ làm những gì native **chưa** có:

* **Gom + giải quyết:** bố cục (F03 context `view`) + trạng thái field (F02) + giá trị + quyền → **một** payload nhất quán, một round trip.
* **Chuẩn hoá activity:** journal native (nhiều thay đổi/journal) → timeline event có kiểu ổn định.
* **Quyền rõ ràng:** boolean dẫn xuất từ link/contract native, frontend không tự suy diễn.

Phần native đã làm tốt thì **dùng lại qua `_links`**, không bọc lại: relations, transitions (status cho phép), attachments, watchers, ghi mọi thứ.

> **F04 không có đường ghi.** Sửa field, đổi status, comment, relation, upload đều đi qua **API v3 native**. F04 không tạo bề mặt ghi/authorization mới.

> **Presentation ≠ Configuration ≠ Authorization.** Bố cục thuộc F03, trạng thái field thuộc F02, quyền thuộc OpenProject.

```text
Frontend riêng (Vue/React)
        │ HAL JSON
┌───────▼───────────────────────────────────────────┐
│ modules/issue_view (read-only, API v3)            │
│   Builder ─► Screens::Resolver (F03)   [optional] │
│           ─► FieldRules (F02)          [optional] │
│           ─► native WorkPackage / Journal / schema│
└───────┬───────────────────────────────────────────┘
        ▼  OpenProject CE (không sửa core)
```

| Jira | OpenProject / F04 |
|---|---|
| Issue key `PROJ-123` | `WorkPackage#display_id` (semantic hoặc số, FR-02) |
| Summary / Reporter | `subject` / `author` |
| Component | `category` |
| Sprint | `version` hoặc Sprint của `backlogs` nếu bật |
| Epic / Story / Sub-task | type + parent/children native |
| Issue links | `Relation` native |
| Transition | đổi sang status mà workflow native cho phép (FR-23) |

## 2. Mục tiêu và phi mục tiêu

### 2.1 Mục tiêu

* Endpoint khởi tạo `issue_view` (header, bố cục + giá trị + trạng thái field, quyền, counts).
* Endpoint activity đã chuẩn hoá (lazy, phân trang).
* Hợp đồng ổn định, có OpenAPI + contract test.
* Suy giảm êm về layout native khi F02/F03 vắng hoặc lỗi.

### 2.2 Phi mục tiêu (MUST NOT)

* Không model/bảng/migration mới; không sửa core; không thêm cột vào bảng core.
* **Không endpoint POST/PUT/PATCH/DELETE** (FR-24). Không comment API riêng, không transition POST riêng.
* Không endpoint relations / transitions / attachments / watchers riêng ở V1 (FR-22).
* Không tự cài authorization; không suy quyền từ quan hệ ("user == assignee").
* Không workflow engine, automation, validator.
* Không hard-code layout theo type.
* Không dashboard, search, bulk edit, advanced linking (F05–F08).
* Không xây frontend trong repo.

## 3. Ngữ cảnh codebase đã/ cần xác minh

| # | Giả định | Nơi kiểm chứng | Trạng thái |
|---|---|---|---|
| C1 | Activity native: `GET/POST /work_packages/{id}/activities`, `GET/PATCH /activities/{id}`; **không DELETE**. | `lib/api/v3/activities/activities_api.rb:43,52`; `activities_by_work_package_api.rb:42,63` | ✅ |
| C2 | `Setting.work_packages_identifier` ∈ classic/semantic; dùng `Setting::WorkPackageIdentifier.semantic?`. | `config/constants/settings/definition.rb:1491`, `app/models/setting/work_package_identifier.rb` | ✅ |
| C3 | `/api/v3/views` đã có ⇒ không đặt tên `view`; `issue_view` không đụng tên nào. | `lib/api/v3/views` | ✅ |
| C4 | F03: `Screens::Resolver.for(project, type, context)` (fallback `view→edit→native`), `ResolvedScreen` (`source, reason, context, screen, sections, state_source, diagnostics`); field hash `{key,label,position,width,state}`; section `{id,name,position,fields}`; **Ruby dùng snake_case** (`hidden_but_placed`, `required_not_placed`, `unavailable`, `skipped`), camelCase chỉ ở tầng API ⇒ F04 phải ánh xạ, id section thành chuỗi. Fail-open trả `native(:error, error: true)`. | `modules/screens/app/services/screens/resolver.rb:262,290-305`, `resolved_screen.rb` | ✅ (shape `diagnostics.error` ở resolver.rb:305+ cần đọc) |
| C5 | Quy ước F01–F03: API v3 HAL camelCase, `_type`, định danh lỗi API v3, fail-open + `Rails.error.report`, cache theo request. | spec F01/F02/F03 §7, §14 | ✅ (đọc để theo) |
| C6 | WP representer: link `update` là **POST tới form** (`representer:67`), PATCH trực tiếp là **`updateImmediately`** (`:83`); `delete` (`:93`), `addWatcher` (`:231`), `removeWatcher` (`:241`), `addRelation` (`:250`), `addComment` (`:279`); `addAttachment` ở `lib/api/v3/attachments/attachable_representer_mixin.rb:58`; `logTime` ở `modules/costs/lib/costs/engine.rb:291` (chỉ khi `log_time_allowed?`). | các file nêu | ✅ |
| C7 | Status cho phép tính bởi `WorkPackages::BaseContract#assignable_statuses` (`app/contracts/work_packages/base_contract.rb:188`), cũng là nguồn của `schema.status.allowedValues` (`specific_work_package_schema.rb:55`). **Không** có `new_statuses_allowed_to`. Native không có transition có tên. | các file nêu | ✅ |
| C8 | Journal: `Journal#internal` = alias `restricted` (`journal.rb:163`), hiển thị cần quyền `view_internal_comments` (`journal.rb:193-202`); API activity native đã áp `.internal_visible.meeting_cause_visible` (`activities_by_work_package_api.rb:47`); POST nhận `internal` (`:68`). Có emoji reaction (`activities_api.rb:61`, `activity_representer.rb:70,98`) — ngoài phạm vi V1. **`Relation` không journalize** (chỉ có journal "caused by" kiểu `Journal::CausedByWorkPackage*Change`). **`TimeEntry` có journal riêng**, không nằm trong detail của journal WP. Formatter: `lib/open_project/journal_formatter/*`, `activity_property_formatters.rb`. | các file nêu | ✅ (cấu trúc `journal.details` chi tiết còn cần đọc) |
| C9 | Attachments/Watchers/Time entries (costs) đã có API v3. F04 chỉ trả **link + count**. | `lib/api/v3/attachments`, `watchers`, `modules/costs` | ✅ cấu trúc; visibility từng loại cần xác minh |
| C10 | `Relation` 11 loại (`app/models/relation.rb:35-45`); `TYPE_PARENT/TYPE_CHILD` là pseudo-type hierarchy, không phải relation lưu. | `relation.rb:35-50` | ✅ |
| C11 | `{id}` của WP API **chấp nhận semantic identifier** (`PROJ-42`): `work_packages_api.rb:66`, `WorkPackage::SemanticIdentifier::FinderMethods`; cột `work_packages.identifier`; `WorkPackage#display_id` (`semantic_identifier.rb:197`). | các file nêu | ✅ |
| C12 | **Đã xác minh.** `activities` native-theo-WP là `UnpaginatedCollection`, **bỏ qua** `offset/pageSize/filters/sortBy` (`activities_by_work_package_api.rb:38-58`, `activity_collection_representer.rb:32`). `ParamsToQuery` chỉ xử lý filters/sortBy/groupBy, **không** phân trang (`params_to_query.rb:34-74`); phân trang thật dùng `Utilities::Endpoints::Index` + `OffsetPaginatedCollection` (`endpoints/index.rb:92-116`). `offset` = số trang 1-based, `<1`/không phải số ⇒ trang 1 (200, không lỗi); `pageSize`: `-1` hoặc `> apiv3_max_page_size` ⇒ kẹp max; `0`/không phải số ⇒ trang rỗng, `total` đúng; âm khác `-1` **không được validate** (rủi ro 500) ⇒ phải tự chặn (`offset_paginated_collection.rb:41-45`, `url_props_parsing_helper.rb:34-60`). `sortBy`/`filters` sai tên/toán tử ⇒ 400 `InvalidQuery` (`raise_query_errors.rb`); **JSON hỏng** ⇒ `JSON::ParserError` không được map ⇒ 500 ⇒ phải `rescue` và trả 400 (tiền lệ `attachments_by_container_api.rb:68`). | các file nêu | ✅ |
| C13 | **Đã xác minh.** `GET /work_packages/{id}`: `WorkPackage.visible.find` (`work_packages_api.rb:74`) + `authorize_in_work_package(:view_work_packages){raise NotFound}` (`:76-78`) ⇒ không thấy/không quyền/project archived ⇒ **404** (không 403). Anonymous: 200 nếu role Anonymous có `view_work_packages` trên project public và `login_required` tắt; `login_required` bật ⇒ 401 `Unauthenticated` (`root_api.rb:72-77`). **Cơ chế gắn route:** `add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id do mount … end` (`acts_as_op_engine.rb:229`; ví dụ `modules/costs/lib/costs/engine.rb:282-284`) — class con kế thừa `after_validation` nên `work_package` đã được kiểm visible. F03 dùng `authorize_logged_in` (anonymous ⇒ 403) — **không** áp dụng cho F04. | các file nêu | ✅ |

## 4. Thuật ngữ

| Thuật ngữ | Nghĩa |
|---|---|
| Issue View | Payload chỉ đọc mô tả trang chi tiết một WP (§6). |
| Header | Vùng cố định: `identifier, subject` + `type, status, priority, assignee, author`. **Không** do screen quyết định, **không** áp F02 `hidden`. |
| Layout | Sections → fields do F03 (context `view`) hoặc native. |
| `state` | `{required, readOnly, defaultValue}` từ F02. |
| `editable` | Gợi ý UI "có nên cho sửa inline" (FR-09). Native vẫn là người quyết. |
| Event | Bản ghi activity đã chuẩn hoá (§7). |

## 5. Quan hệ giữa các feature và thứ tự đánh giá

| Feature | Trả lời |
|---|---|
| F01 | Type nào dùng được trong project? |
| F02 | Field hidden/required/read-only/default? |
| F03 | Field nằm đâu, theo context nào? |
| **F04** | **Gom tất cả + dữ liệu thật của một WP.** |
| Native | Ai làm được gì, status nào đi tiếp được? |

```text
Request ─► WP visible theo native? (không ⇒ 404)
        ─► Screens::Resolver(project, type, :view) → sections/fields  (hoặc native)
        ─► giá trị field từ WP + schema native (kiểu, writable)
        ─► permissions từ link/contract native
        ─► editable (FR-09) ─► payload
```

## 6. Issue View Contract (endpoint khởi tạo)

`GET /api/v3/work_packages/{id}/issue_view` — `_type: "IssueView"`. `{id}` là id số **hoặc** semantic identifier (như native, C11). Ví dụ rút gọn:

```json
{
  "_type": "IssueView",
  "id": 12345,
  "identifier": "PROJ-123",
  "subject": "Login fails on mobile",
  "source": "screen",
  "reason": null,
  "header": {
    "type":     { "id": 7,  "name": "Bug",  "_links": { "self": { "href": "/api/v3/types/7" } } },
    "status":   { "id": 1,  "name": "Open", "isClosed": false, "_links": { "self": { "href": "/api/v3/statuses/1" } } },
    "priority": { "id": 4,  "name": "High", "_links": { "self": { "href": "/api/v3/priorities/4" } } },
    "assignee": { "id": 18, "name": "Kaito", "_links": { "self": { "href": "/api/v3/users/18" } } },
    "author":   { "id": 20, "name": "An",    "_links": { "self": { "href": "/api/v3/users/20" } } }
  },
  "sections": [
    { "id": "1", "name": "Details", "position": 1,
      "fields": [
        { "key": "priority", "label": "Priority", "dataType": "link", "position": 1, "width": "half",
          "value": { "raw": 4, "display": "High" },
          "state": { "required": true, "readOnly": false, "defaultValue": null },
          "editable": true, "editableReason": null },
        { "key": "description", "label": "Description", "dataType": "formattable", "position": 2, "width": "full",
          "value": { "format": "markdown", "raw": "…", "html": "<p>…</p>" },
          "state": null, "editable": true, "editableReason": null }
      ] }
  ],
  "permissions": { "view": true, "edit": true, "delete": false, "comment": true, "transition": true,
                   "addRelation": true, "manageWatchers": false, "addAttachment": true, "logTime": false },
  "counts": { "comments": 3, "children": 3, "relations": 2, "attachments": 1, "watchers": 4 },
  "parent": { "id": 12, "identifier": "EPIC-12", "subject": "Login Improvements" },
  "lockVersion": 5,
  "_links": {
    "self": { "href": "/api/v3/work_packages/12345/issue_view" },
    "workPackage": { "href": "/api/v3/work_packages/12345" },
    "updateImmediately": { "href": "/api/v3/work_packages/12345", "method": "patch" },
    "activities": { "href": "/api/v3/work_packages/12345/issue_view/activities" },
    "addComment": { "href": "/api/v3/work_packages/12345/activities", "method": "post" },
    "relations": { "href": "/api/v3/work_packages/12345/relations" },
    "children": { "href": "/api/v3/work_packages?filters=[{\"parent\":{\"operator\":\"=\",\"values\":[\"12345\"]}}]" },
    "attachments": { "href": "/api/v3/work_packages/12345/attachments" },
    "watchers": { "href": "/api/v3/work_packages/12345/watchers" },
    "allowedStatuses": { "href": "/api/v3/work_packages/12345/form", "method": "post" }
  }
}
```

(`diagnostics` chỉ xuất hiện cho admin, FR-12.)

### 6.1 Yêu cầu

* **FR-01 Quy ước.** camelCase, `_type`, `_links` HAL, thời gian ISO-8601 UTC, `id` số. `key` của field dùng **snake_case** giống F03 (`due_date`, `custom_field_12`).
* **FR-02 Định danh.** `identifier = work_package.display_id` (C11): semantic nếu `Setting::WorkPackageIdentifier.semantic?` và WP có identifier; ngược lại id số dạng chuỗi. Dẫn xuất khi đọc, **không lưu, không cache**. WP chuyển project ⇒ identifier theo project hiện tại. Path nhận id số hoặc semantic (như native); sai/không thấy ⇒ 404.
* **FR-03 Header.** Luôn có `identifier, subject, header.{type,status,priority,assignee,author}` (giá trị `null` nếu chưa gán). Header **bằng giá trị** field cùng khoá trong `sections` nếu có; không có annotation `editable`.
* **FR-04 Layout từ F03** (`source = "screen"`): dùng sections/fields của `Screens::Resolver.for(project, type, :view)`, giữ `position`, `width ∈ {full, half}`, `state`; section `id` thành chuỗi; thêm `dataType`, `value`, `editable`, `editableReason`. `reason: null`.
* **FR-05 Layout native** (`source = "native"`): một section cho mỗi attribute group của schema native (`_attributeGroups`, loại group query/bảng liên quan ở V1); `id` = key group, `name` = tên group, `position` = chỉ số+1, field `width: "full"`, `state: null`. `reason` ∈ {`no_scheme, scheme_inactive, type_not_in_scheme, no_usable_screen, error`} từ F03, hoặc `module_disabled` khi F03 không cài/tắt. `reason: "error"` là tín hiệu suy giảm duy nhất cho client (không có thêm cờ).
* **FR-06 Giá trị.** Mỗi field có đúng một `value` theo `dataType` (§6.1.1), tính từ **schema native** (không đoán theo tên). `display` đã dịch theo locale và định dạng ngày/số của người dùng. Kiểu chưa hỗ trợ ⇒ `dataType: "unknown"`, `value: {raw: null, display: null}`, `editable: false` (không `to_s` đối tượng).
* **FR-07 Field không dùng được.** Field có trong layout nhưng không khả dụng/không xem được (custom field tắt, không có quyền xem) ⇒ **loại khỏi `fields`**, không lỗi.
* **FR-08 Quyền.** Cả 9 khoá `permissions` luôn hiện, kiểu boolean (module tắt ⇒ `false`), nguồn duy nhất `IssueView::Permissions` (không rải `allowed_to?`):

  | khoá | nguồn |
  |---|---|
  | `view` | `true` (đã qua kiểm tra visible) |
  | `edit` | có link `updateImmediately` (hoặc `update`) |
  | `delete` | có link `delete` |
  | `comment` | có link `addComment` |
  | `transition` | `edit` ∧ `assignable_statuses` (C7) có ít nhất một status khác status hiện tại |
  | `addRelation` | có link `addRelation` |
  | `manageWatchers` | có `addWatcher` hoặc `removeWatcher` |
  | `addAttachment` | có link `addAttachment` |
  | `logTime` | có link `logTime` (costs) |

  Link trong `_links` của payload chỉ xuất hiện khi quyền tương ứng `true`.
* **FR-09 `editable`.** `editable = permissions.edit ∧ schema[key].writable ∧ ¬state.readOnly`. Với `status`: `editable ⇔ permissions.transition`. `editable = true ⇒ editableReason = null`; ngược lại lấy **một** lý do theo thứ tự ưu tiên `locked > no_permission > not_writable > read_only > workflow`, trong đó `locked` = native không cho sửa WP (project archived/version đóng…), `workflow` chỉ áp cho `status`. **Chỉ là gợi ý**; native vẫn chặn khi ghi. Test đối chiếu với `POST /work_packages/{id}/form` cho cùng user (không lệch).
* **FR-10 Counts.** Chỉ tính khi WP đã `WorkPackage.visible`. `comments` = số journal có `notes` trong scope `internal_visible.meeting_cause_visible` (cùng scope với activities); `children` = `WorkPackage.visible(user)` con trực tiếp (`.where(parent_id:)`); `relations` = `Relation.visible(user)` (cả hai đầu phải visible, `app/models/relations/scopes/visible.rb:49`), **không** gồm parent/children; `attachments` = số attachment của WP, **vắng khoá** nếu project `deactivate_work_package_attachments?`; `watchers` **vắng khoá** nếu user không có `view_work_package_watchers` ở project. Không có `counts.activities`. (`costs`/`backlogs` không đổi các quy tắc visible này.)
* **FR-11 `lockVersion`** = `lock_version` native từ đúng bản WP đã dùng dựng payload (một lần load).
* **FR-12 `diagnostics`** (camelCase: `unavailable[]`, `hiddenButPlaced[]` — mảng key; ánh xạ từ snake_case F03) **chỉ trả cho admin**; người khác không có khoá này (tránh lộ field/tên custom field không xem được). `requiredNotPlaced`/`skipped` **không** đưa vào (vô nghĩa ở context `view`).
* **FR-13 Phụ thuộc mềm / fail-open.** F03 không cài/tắt ⇒ `native` + `reason: module_disabled`; F02 vắng ⇒ `state: null`. Lỗi trong F02/F03/builder ⇒ `Rails.error.report(handled: true)` + log, trả layout native `reason: "error"`, vẫn 200 với header + quyền. Chỉ lỗi khi không đọc được chính WP.
* **Parent:** `parent` là `{id, identifier, subject}` **chỉ nếu visible**; ngược lại `null` (không lộ tiêu đề). Không có `_links.parent.title` khi invisible.

#### 6.1.1 `dataType` / `value`

| `dataType` | Ví dụ | `value` |
|---|---|---|
| `string` | `subject` | `{raw, display}` |
| `formattable` | `description` | `{format, raw, html}` — `html` do OpenProject sanitize |
| `integer`/`float`/`duration` | `estimated_time` | `{raw, display}` (duration ISO-8601) |
| `date`/`datetime` | `due_date` | `{raw: ISO, display}` |
| `bool` | custom field | `{raw, display}` |
| `link` | priority, status, assignee, category, version, user/list custom field | `{raw: id, display: name}` |
| `linkList` | multi-select custom field | `{raw: [ids], display: [names]}` |
| `unknown` | kiểu chưa hỗ trợ | xem FR-06 |

### 6.2 Bảng mã trả về (mọi endpoint của module)

| Tình huống | HTTP | Định danh lỗi (API v3) |
|---|---|---|
| Thành công | 200 | — |
| Chưa đăng nhập, `login_required` bật (hoặc native yêu cầu đăng nhập) | 401 | `Unauthenticated` |
| WP/project không thấy (kể cả anonymous khi Anonymous role thiếu `view_work_packages`), project archived, id không tồn tại, thiếu quyền | 404 | `NotFound` (**không bao giờ 403**; **không** dùng `authorize_logged_in`) |
| `filters`/`sortBy` sai tên/toán tử/giá trị; JSON hỏng; `pageSize` âm ≠ -1 | 400 | `InvalidQuery` (JSON hỏng/`pageSize` âm: endpoint tự `rescue`/chặn, không để 500) |
| Lỗi nội bộ endpoint lazy | 500 | `InternalServerError` (không fail-open ở lazy) |

## 7. Activity Timeline (lazy)

`GET /api/v3/work_packages/{id}/issue_view/activities` — collection API v3 (C12; **phải** dùng `OffsetPaginatedCollection`, native activities không phân trang): `offset` (số trang 1-based; `<1`/không phải số ⇒ 1), `pageSize` (mặc định 20; `-1` hoặc > `min(100, apiv3_max_page_size)` ⇒ kẹp; `0`/không phải số ⇒ trang rỗng; âm khác `-1` ⇒ 400), `sortBy=[["timestamp","asc"]]` (khoá duy nhất `timestamp`, mặc định `asc`), `filters=[{"type":{"operator":"=","values":["COMMENT"]}}]` (chỉ lọc `type`). Tham số sai ⇒ 400 `InvalidQuery`. Envelope: `total, count, pageSize, offset, _embedded.elements`. **Đơn vị phân trang = journal** (không phải event) để event của một journal không bị cắt giữa hai trang; `total` = số journal hiển thị.

* **FR-14 Nguồn & visibility.** Normalizer **bắt đầu từ scope native** `work_package.journals.internal_visible.meeting_cause_visible` (C8; dùng `User.current`, đúng trong request) và lấy chi tiết từ `journal.details` (hash `{key => [old,new]}`, **giữ thứ tự chèn**) + `JournalFormatter#render_detail` (cả `html: false` và `html: true`) cho chuỗi mô tả. **Không** truy vấn thẳng bảng journals, **không** parser song song. Bỏ detail mà `render_detail` trả `nil` hoặc `""` (vd. cause meeting ẩn). Journal nội bộ user không xem được ⇒ **toàn bộ** event của nó biến mất.
* **FR-15 Tách event.** Một journal ⇒ N event: `COMMENT` (nếu `notes` không rỗng) **trước**, rồi mỗi detail theo thứ tự `journal.details`. `id` = `"<journalId>:comment"` hoặc `"<journalId>:<n>"`, `n` 0-based trên các detail **còn lại sau khi lọc**. Sắp xếp journal theo `(created_at, id)`; event trong journal theo thứ tự trên. Journal rỗng (không notes, không detail hiển thị) ⇒ không sinh event.
* **FR-16 Hợp đồng event** và tập `type` **đóng** V1:

  | `type` | Khi nào | Trường riêng |
  |---|---|---|
  | `COMMENT` | journal có `notes` | `comment: {id, body: {format, raw, html}, internal, createdAt, updatedAt}` + link `update` chỉ khi native cho phép |
  | `FIELD_CHANGED` | mọi key khác (`subject`, `*_id`, ngày, `description`, `target_versions`, `custom_fields_N`…) | `field` (key trong `journal.details`), `raw: {from, to}` (giá trị thô trong details: id/chuỗi), `description: {raw, html}` (từ `render_detail`; formatter đã che tên đối tượng không xem được bằng placeholder). **Không** có `from.display/to.display` riêng (formatter chỉ trả một câu hoàn chỉnh) — xem Q-H |
  | `ATTACHMENT_ADDED` | key `attachments_<id>` có old=nil (id nằm ở hậu tố key) | `attachment: {id, fileName}`; link attachment chỉ khi còn tồn tại |
  | `ATTACHMENT_REMOVED` | key `attachments_<id>` có new=nil | `attachment: {id, fileName}` (không link) |
  | `OTHER` | `cause` (journal gây bởi thay đổi hệ thống, gồm thay đổi relation/parent/predecessor làm đổi ngày; dùng `cause.type`), `file_links_N`, `custom_comment*`, `project_phase*`, `agenda_items*`, `participants*` | `description: {raw, html}`, `causeType` nếu có |

  Chung: `_type: "IssueViewEvent"`, `id`, `journalId`, `type`, `actor {id,name,_links}`, `timestamp`. Frontend chỉ `switch(type)`; giá trị lạ ⇒ render chung. **Bỏ** `STATUS_CHANGED`/`ASSIGNEE_CHANGED` (là `FIELD_CHANGED` với `field`), `RELATION_*` (relation không journalize, C8), `WORK_LOGGED` (time entry journal riêng, C8). Nếu sau này cần, mở rộng bằng feature riêng.
* **FR-17 Comment nội bộ.** `comment.internal` phản ánh `Journal#internal`; user không có `view_internal_comments` không thấy event nào của nó và không tính vào `counts.comments`.
* **FR-18 Không ghi.** Sửa comment dùng native `PATCH /activities/{id}`; thêm dùng `POST /work_packages/{id}/activities`; **xoá không có** (C1). Không có endpoint ghi ở module.
* **FR-19 Không N+1.** Preload actor/avatar/details theo lô (test đếm truy vấn §14).
* Emoji reaction: ngoài phạm vi V1.
* **Mapping tham chiếu (đã xác minh, C8):** iterate `journal.details`; `attachments_\d+` → ADDED/REMOVED theo old/new nil; `cause` → OTHER; `custom_fields_\d+` → FIELD_CHANGED (formatter đã ẩn field không có quyền; `nil` ⇒ bỏ); các key còn lại → FIELD_CHANGED. `version_id` bị native bỏ khỏi details. Field người (assignee/responsible/author) formatter luôn hiện tên (không kiểm visible) — giống hành vi native, chấp nhận.

## 8. Relations, hierarchy, transitions (dùng native)

* **FR-20 (đổi thành quy tắc phạm vi).** V1 **không** có endpoint `issue_view/relations` hay `issue_view/transitions`. Frontend dùng native qua `_links`: `relations`, `children` (filter `parent`), `allowedStatuses` (form native, `allowedValues` của `status`). F04 chỉ cung cấp `counts`, `parent` (visible), `permissions.transition`.
* **FR-21 Chuyển trạng thái.** Luôn là `PATCH /work_packages/{id}` native với link `status` + `lockVersion` (native kiểm workflow, quyền, validator). Không có `POST …/transitions/:id`. Không đặt tên transition ("Start Progress"); tên = tên status đích.
* **FR-22 Ngưỡng bổ sung.** Chỉ thêm `issue_view/relations` (nhóm theo loại/hướng, lọc visible) hoặc `issue_view/transitions` nếu **đo được** vấn đề (số round trip/độ trễ) — làm ở feature sau, kèm bằng chứng.
* **FR-23** F03 context `transition` **không** phơi ở V1 (chưa có consumer; **[Q-C]**).

Hiển thị loại relation do frontend; loại relation mở rộng thuộc F08.

## 9. Quyết định thiết kế

### 9.1 Ánh xạ từ bản nháp cũ

| Bản nháp cũ | Quyết định |
|---|---|
| `/api/jira/issues/:id/view` | `/api/v3/work_packages/{id}/issue_view` (HAL, quy ước F03; không "jira") |
| `GET /api/jira/issues/:id` | Bỏ (đã có native) |
| `GET/POST/PUT/DELETE /comments` | Đọc: `…/issue_view/activities` (lọc `type=COMMENT`); ghi: native; xoá: không (C1) |
| `…/transitions` GET/POST | Bỏ; dùng `allowedStatuses` + PATCH native |
| `…/relations` | Bỏ ở V1; native + `counts` |
| `jira_issue_view_preferences` | Bỏ (YAGNI, §10) |
| `STATUS_CHANGED`, `ASSIGNEE_CHANGED`, `RELATION_*`, `WORK_LOGGED` | Bỏ/gộp (FR-16) |
| `fields` + `sections` | Chỉ `sections[].fields[]` |
| ETag/304 | Bỏ ở V1 (FR-27) |

### 9.2 Câu hỏi mở (mặc định)

* **Q-A** Fallback layout `view`: native (`source: native`), header luôn có.
* **Q-C** Phơi F03 `transition` screen: **không**.
* **Q-D** Id trong path: **số hoặc semantic** (đã xác minh C11).
* **Q-E** Endpoint đa WP: **không** (F05).
* **Q-H** Có resolve tên cho `raw.from/to` (status, priority, type, assignee…) để frontend hiện "Open → In Progress" không? Mặc định **không** ở V1 (dùng `description`); nếu cần, thêm resolver theo allowlist key + scope visible, ở feature riêng.
* **Q-F** (đã giải quyết, C13) Truy cập ẩn danh: **theo native** của `GET /work_packages/{id}` (project public ⇒ cho phép; nếu native cần đăng nhập ⇒ 401). Ghi rõ trong spec.
* **Q-G** Feature flag cho module: mặc định **tắt** ở môi trường production cho tới khi agent/chủ sản phẩm bật; module tắt ⇒ route 404.

## 10. Dữ liệu

**Không bảng mới, không migration.** Preference giao diện (layout mode, tab mặc định) do frontend tự lưu hoặc dùng user preference native; ngoài phạm vi.

## 11. Bảo mật

* **MUST** gắn route bằng `add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id` (C13) để kế thừa `WorkPackage.visible` + `view_work_packages` của native; **MUST NOT** dùng `authorize_logged_in` hay thêm `authorize` riêng cho quyền xem WP (sẽ trả 403/401 sai). Mọi kiểm tra bổ sung phải `raise NotFound`.
* **MUST NOT** tự cài quyền. `permissions`/`editable` **không phải enforcement** — frontend vẫn gọi native; test chứng minh native chặn khi `permissions` bị giả mạo.
* Không rò: comment nội bộ + counts (FR-10/17), WP đích/parent không thấy (FR-10, parent), field không xem được (FR-07), `diagnostics` (FR-12), `display` của đối tượng không xem được dùng formatter native.
* `html` do OpenProject sanitize; `display` là chuỗi thuần (frontend escape). Không log nội dung người dùng.
* **FR-27 Cache.** Response: `Cache-Control: private, no-cache`, `Vary: Authorization, Cookie, Accept-Language`; **không ETag/304** ở V1 (không bảo đảm phủ thay đổi quyền/relation/attachment). Cache chỉ trong request (`RequestStore`), **không** `Rails.cache` dùng chung.
* **FR-24 Không ghi:** test route khẳng định module không đăng ký route ghi.
* **FR-25 Authz:** theo bảng §6.2; ma trận test gồm anonymous, non-member, viewer, member, admin, project archived, WP project khác.
* **FR-26 i18n:** nhãn/thông điệp qua i18n (`en.yml`), không hard-code.

## 12. Frontend (không ràng buộc)

```text
IssuePage
├── IssueHeader     ← header, permissions.transition, allowedStatuses
├── IssueSummary    ← subject
├── IssueBody       ← sections[] (renderer generic, KHÔNG if type == ...)
├── IssueActivity   ← activities (switch event.type)
└── IssueRelations  ← relations/children/attachments qua _links native
```

Thêm "Bug View/Story View" = thêm screen F03, không sửa component. Frontend render `html` đã sanitize, không `innerHTML` trên `raw`; gửi `lockVersion` khi PATCH native và xử lý 409 `UpdateConflict`. Không thêm Angular/Stimulus vào core cho feature này.

## 13. Yêu cầu phi chức năng

* **Hiệu năng:** số truy vấn endpoint khởi tạo với 5 field **bằng** với 50 field (assert bằng nhau); trần tuyệt đối do agent đo baseline rồi cố định trong spec và test. Preload custom field values; `permissions` dùng một lần tra quyền preload, không gọi riêng từng link; `counts` dùng truy vấn nhóm.
* **Tương thích ngược:** module tắt ⇒ OpenProject chạy như cũ.
* **Tài liệu:** OpenAPI `docs/api/apiv3/paths/` + `components/schemas/*_model.yml` cho 2 endpoint; contract test khớp schema.
* **Khả dụng:** payload đủ cho UI truy cập được (`label`, `display`, `editableReason`), không chỉ dựa màu.

## 14. Edge cases agent phải xử lý

* Type có F03 scheme nhưng chưa gán screen `view` ⇒ fallback F03 `view→edit→native`.
* F02 tắt ⇒ `state: null`; F03 tắt ⇒ `native` + `module_disabled`.
* WP đổi type/di chuyển project ⇒ layout, identifier theo type/project hiện tại.
* Custom field bị tắt/xoá sau khi nằm trên screen ⇒ bỏ khỏi `fields`.
* Field F02 `hidden` đặt trên screen ⇒ đã bị F03 lọc.
* Parent/relation/children không visible ⇒ không lộ (parent `null`, count không tính).
* Journal rỗng, nhiều detail, chỉ có comment, comment đã sửa (`updatedAt ≠ createdAt`), detail kiểu lạ ⇒ `OTHER`.
* Journal nội bộ + user thiếu quyền ⇒ biến mất hoàn toàn.
* Status hiện tại không còn trong workflow ⇒ `transition: false`, không lỗi.
* WP bị khoá (project archived…) ⇒ `edit: false`, `editableReason: "locked"`.
* Locale thiếu bản dịch ⇒ rơi về `en`.
* Hai người sửa đồng thời ⇒ `lockVersion` trong payload nhất quán với bản đã đọc; 409 xử lý ở native.

## 15. Tiêu chí chấp nhận (Definition of Done)

- [ ] `issue_view` trả `IssueView` đúng §6 (FR-01…FR-13), `activities` đúng §7 (FR-14…FR-19)
- [ ] Mọi FR có test; bảng truy vết §17 xanh hết
- [ ] OpenAPI 2 endpoint + contract test
- [ ] Không có route ghi (FR-24); không bảng/migration; không sửa core
- [ ] Ma trận authz (FR-25) + test rò rỉ (internal, WP đích, parent, field, diagnostics)
- [ ] Không N+1 (test bằng nhau 5 vs 50 field); `pageSize` bị kẹp
- [ ] i18n; không "jira" trong tên bảng/class/route/permission/menu/i18n/file
- [ ] rubocop sạch; spec & plan đã commit/được duyệt
- [ ] Module tắt ⇒ 404 (Q-G)

**Không làm:** workflow engine, automation, advanced linking, dashboard, search, bulk edit, relations/transitions endpoint riêng, frontend.

## 16. Cắt lát

```text
01 → 02 → 03 → 04 ★ Issue View → 05 Navigator → 06 Saved Filters → 07 Bulk → 08 Enhanced Linking
```

* **Slice 1:** module + Builder + `issue_view` (header, layout native/F03, giá trị, permissions, counts, parent) + OpenAPI + test authz/leak.
* **Slice 2:** `activities` + normalizer (kèm đọc `journal.details`, xác nhận C8) + test.
* **Slice 3:** hardening: query-count, fail-open, contract test, flag.

Độ khó: **M** (backend, không UI/DB).

## 17. Kịch bản kiểm thử và truy vết FR

| # | Kịch bản | FR |
|---|---|---|
| 1 | Screen `view` F03 ⇒ sections đúng thứ tự/`width`; field F02 `hidden` vắng | 04 |
| 2 | Project không scheme ⇒ `native` + sections từ `_attributeGroups` | 05 |
| 3 | F03 báo lỗi giả lập ⇒ 200 `native`, `reason: error`, log; F02 vắng ⇒ `state: null`; F03 tắt ⇒ `module_disabled` | 13 |
| 4 | Assignee `null` ⇒ header `assignee: null` | 03 |
| 5 | Semantic ⇒ `PROJ-123`; classic ⇒ `"12345"`; path nhận cả hai; WP chuyển project ⇒ key mới | 02 |
| 6 | Giá trị theo từng `dataType`; kiểu lạ ⇒ `unknown`, `editable:false`; locale/ngày theo user | 06 |
| 7 | Custom field tắt/không xem ⇒ vắng khỏi `fields` | 07 |
| 8 | User chỉ-xem: `edit:false`, `editable:false` lý do `no_permission`; ma trận 9 khoá + link vắng tương ứng; PATCH native bị chặn dù payload giả | 08, 25 |
| 9 | F02 `readOnly` ⇒ `read_only`; WP khoá ⇒ `locked`; thứ tự ưu tiên; parity với `/form` | 09 |
| 10 | Status: có/không đích khả dụng ⇒ `transition` đúng; WP "mồ côi" status | 08, 21 |
| 11 | Counts: user thiếu `view_internal_comments`, relation tới WP không thấy, children không thấy, attachments/watchers vắng khoá | 10 |
| 12 | `lockVersion` khớp WP; đổi WP ⇒ giá trị mới | 11 |
| 13 | `diagnostics` chỉ admin, camelCase | 12 |
| 14 | Parent không thấy ⇒ `parent: null` không lộ title | parent |
| 15 | Journal `notes` + 2 detail ⇒ 3 event, id `:comment`, `:0`, `:1`, thứ tự cố định; phân trang theo event | 15 |
| 16 | Detail attachment thêm/gỡ, detail lạ/caused-by ⇒ `OTHER` | 16 |
| 17 | Journal nội bộ: user thiếu quyền không thấy event nào (kể cả detail) | 14, 17 |
| 18 | `pageSize=1000` ⇒ kẹp; `pageSize=-5` ⇒ 400; `offset=0`/`abc` ⇒ trang 1; `pageSize=0` ⇒ rỗng + `total`; `sortBy`/`filters` lạ hoặc JSON hỏng ⇒ 400 `InvalidQuery` (không 500); filter `type=COMMENT`; phân trang theo journal | 14, 15 (C12) |
| 19 | Sửa comment qua native `PATCH`; xoá ⇒ không có | 18 |
| 20 | Query count: 5 vs 50 field bằng nhau; activity preload | 19, 13 |
| 21 | Không có `issue_view/relations` & `transitions`; không route ghi | 20, 22, 24 |
| 22 | PATCH status native với `lockVersion` cũ ⇒ 409 | 21 |
| 23 | Ma trận authz: anonymous, non-member, viewer, member, admin, archived, WP project khác | 25 |
| 24 | Header cache/Vary; không ETag | 27 |
| 25 | i18n: không chuỗi cứng; không "jira" | 26 |
| 26 | Module tắt ⇒ 404 | Q-G |

## 18. Đầu ra mong đợi từ agent

1. Spec `docs/superpowers/specs/<ngày>-issue-view-design.md` (đối chiếu code C1–C13 (đều đã xác minh, xem Phụ lục A); quyết định; rủi ro; Q-x chọn mặc định).
2. Plan: task có thứ tự, tiêu chí hoàn thành, test, truy vết FR.
3. Implementation `modules/issue_view` + test + OpenAPI; không đụng core.

---

## Phụ lục A — Hội đồng review & revise

Hội đồng: **(A)** kiểm chứng code, **(B)** độ sẵn sàng cho AI agent, **(C)** bảo mật/thiết kế API. Vòng 1 trên bản nháp đầu; vòng 2 là bản này.

| Vấn đề phát hiện | Nguồn | Xử lý |
|---|---|---|
| `/api/jira/*`, tên "jira" trái quy ước F01–F03 | tự rà | `/api/v3/…/issue_view`, cấm "jira" |
| `new_statuses_allowed_to` không tồn tại; `update` là POST form, PATCH là `updateImmediately` | A | C6/C7 sửa; FR-08/09 dùng link/contract đúng |
| Relation không journalize; time entry journal riêng ⇒ `RELATION_*`, `WORK_LOGGED` không dựng được | A | bỏ khỏi tập event (FR-16) |
| Semantic identifier **đã** nhận trong path; có `display_id` | A | FR-02, Q-D, C11 |
| `diagnostics` Ruby snake_case; shape field/section | A | C4, FR-12 ánh xạ |
| ETag/304 stale + rò quyền | B, C | bỏ ETag, `Cache-Control private`, `Vary` (FR-27) |
| Counts rò comment nội bộ/WP không thấy; `counts.activities` mơ hồ | B, C | FR-10 cùng scope, bỏ `activities` |
| Normalizer rò journal nội bộ/ detail | C | FR-14: bắt đầu từ scope native + formatter native |
| Endpoint relations/transitions chỉ bọc lại native | C | FR-20/22: bỏ ở V1, dùng `_links` |
| Pagination/filter lệch API v3 (offset = số trang, sortBy JSON) | C | §7, C12 |
| `diagnostics` lộ tên field không xem được | C | admin-only (FR-12) |
| `editable` tự suy ⇒ lệch native | C, B | FR-09 + parity test với `/form`, thứ tự ưu tiên lý do |
| FR đánh số sai, tham chiếu chéo gãy, §16 vs §17 | B | đánh số lại FR-01…27, bảng truy vết §17 |
| 401 vs 404 mâu thuẫn | B, C | bảng §6.2 + Q-F theo native |
| Thiếu bảng lỗi/envelope/thứ tự event/ordinal | B | §6.2, §7 FR-15 |
| Nguồn layout native chưa xác định | B | FR-05 |
| Header vs sections trùng | B | FR-03 |
| ETag, `unknown` `to_s`, query budget mơ hồ, flag, DoD | B, C | FR-06, §13, Q-G, §15 |
| Frontend/tiền tố "erb_lint" thừa | B | loại bỏ |

**Đã xác minh sau vòng 2 (hội đồng kiểm chứng):** C12 (phân trang/lỗi tham số), C13 (anonymous + cơ chế gắn route), cấu trúc `journal.details` + mapping event, quy tắc visible của counts. Các phát hiện làm đổi thiết kế: activities phân trang theo **journal** (native không phân trang), JSON filter hỏng phải tự `rescue` (native trả 500), `pageSize` âm phải tự chặn, `FIELD_CHANGED` không có `from/to.display` (thay bằng `raw` + `description`), `diagnostics`/counts theo quy tắc visible thật.

**Còn mở (ghi trong spec):** chỉ còn chi tiết triển khai — (1) giá trị mặc định `view_permission` của attachments (nhiều khả năng `view_work_packages`, xác nhận khi implement); (2) shape `diagnostics.error` ở `resolver.rb:305+`; (3) hành vi project archived đã suy từ scope `allowed_to`, cần test chạy thật; (4) Q-H.
