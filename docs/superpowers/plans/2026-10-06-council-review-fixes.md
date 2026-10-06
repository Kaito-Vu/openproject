# Kế hoạch sửa — kết quả hội đồng review Feature 01/02/03

Phạm vi: `modules/type_schemes` (F01), `modules/field_rules` (F02), `modules/screens` (F03), `docs/ideas/*`, `docs/superpowers/specs/*`, `docs/api/apiv3/**`.
Đường dẫn bên dưới tính từ gốc repo. Mọi finding đều rút từ review tĩnh (chưa chạy Ruby) → **mỗi task: đọc lại code tại vị trí nêu trước khi sửa, nếu khác thì theo code thật**.

## Quy tắc chung cho agent

- Không sửa core ngoài module; không thêm dependency; sửa tối thiểu, theo style file xung quanh.
- Mỗi task có spec đi kèm (RSpec). Máy dev Windows không có Ruby → chạy `bundle exec rspec <path>` trong Docker/CI; nếu không chạy được thì nói rõ, không tuyên bố "pass".
- Không commit trừ khi được yêu cầu. Một task = một nhóm thay đổi nhỏ, dễ review.
- Thứ tự: Pha 0 (quyết định) → Pha 1 (bug runtime) → Pha 2 (bảo mật/chính sách) → Pha 3 (hiệu năng/độ bền) → Pha 4 (docs/API) → Pha 5 (test).
- Các Pha 1–3 chia theo module nên 3 agent chạy song song được; Pha 4 sau cùng vì phụ thuộc kết quả.

## Pha 0 — Quyết định (mặc định đã chọn, đổi nếu chủ dự án muốn)

| ID | Câu hỏi | Mặc định áp dụng |
|---|---|---|
| D1 | Chính sách đọc (GET) cấu hình | Admin thấy tất cả. User khác: **phải đăng nhập** (không anonymous) và chỉ thấy bản ghi liên quan tới project họ có `view_work_packages` (giống `type_schemes`), còn lại 404. |
| D2 | Toggle auto-assign tắt thì project mới thế nào | "Không scheme" = **không lọc** Type (hành vi native), không fallback về Default. |
| D3 | Fail-open | Giữ fail-open (không được làm sập tạo/sửa work package) nhưng **log error + đếm** (xem T3.4). |

---

## Pha 1 — Bug runtime (cao)

### T1.1 [F01] Toggle `type_scheme_auto_assign_default` không khớp hành vi (D2)
- **Sửa ở:** `modules/type_schemes/app/services/type_schemes/resolver.rb` (`for_project`, ~dòng 30), `modules/type_schemes/lib/api/v3/type_schemes/type_schemes_api.rb` (`visible_schemes`), `modules/type_schemes/config/locales/en.yml` (hint).
- **Hiện trạng:** `for_project` luôn `find_active_scheme || default_scheme`; tắt setting thì project không có `ProjectTypeScheme` nhưng vẫn bị lọc theo Default.
- **Sửa:** khi `Setting.type_scheme_auto_assign_default?` là `false` **và** project không có assignment → `for_project` trả `nil` và `allowed_types`/`type_allowed?` coi như không lọc. Khi setting `true` giữ nguyên fallback Default (để project cũ chưa gán vẫn có scheme). Trong `visible_schemes` chỉ cộng Default cho project chưa gán khi setting bật. Cập nhật hint en.yml cho đúng.
- **Chú ý:** project tạo *trước* khi tắt setting đã có dòng assignment (do migration/listener) nên không đổi.
- **Spec:** `modules/type_schemes/spec/services/type_schemes/resolver_spec.rb` — setting tắt + project không assignment ⇒ mọi enabled type cho phép; setting bật ⇒ lọc theo Default. Thêm vào `spec/requests/api/v3/type_schemes/type_schemes_api_spec.rb` case `visible_schemes` theo setting.

### T1.2 [F02] Wrapper hidden bị chồng/ghi đè
- **Sửa ở:** `modules/field_rules/lib/open_project/field_rules/constraints.rb` (`install`, dòng ~38-42), `modules/field_rules/lib/open_project/field_rules/engine.rb` (~97-101, khối `config.to_prepare`).
- **Hiện trạng:** `TypeVariant.attribute_constraints` (`app/models/type/attributes.rb:55-68`) chỉ có 1 callable/attribute. `to_prepare` chạy lại mỗi reload dev ⇒ wrap chồng; engine khác (costs `engine.rb:510`, backlogs `:250`, budgets `:106`) gọi `add_constraint` sau ⇒ ghi đè wrapper.
- **Sửa:**
  1. Đánh dấu wrapper: tạo lambda có singleton/instance marker (vd. `wrapper.define_singleton_method(:field_rules_wrapper?) { true }`); `install` bỏ qua attribute nếu callable hiện tại đã có marker.
  2. Chuyển việc cài sang `config.after_initialize` (sau khi mọi engine đã `add_constraint`) **và** vẫn gọi trong `to_prepare` (idempotent nhờ marker) để reload dev vẫn đúng.
  3. Thêm `Constraints.verify!` (gọi cuối `after_initialize`): với mỗi attribute allowlist, nếu callable không có marker → `Rails.logger.error` nêu tên attribute (không raise).
- **Spec:** `modules/field_rules/spec/...` — gọi `install` hai lần ⇒ `attribute_constraints[attr]` không lồng 2 lớp (đếm số lần `existing.call` được gọi = 1); mô phỏng engine khác `add_constraint` sau install rồi `install` lại ⇒ hidden vẫn hiệu lực.

### T1.3 [F03] `PATCH item` với position 0 bị đẩy xuống cuối
- **Sửa ở:** `modules/screens/app/services/screens/layout_service.rb` (`place`, ~dòng 66), `modules/screens/lib/api/v3/screens/screens_api.rb` (PATCH item).
- **Sửa:** `place` phân biệt "không truyền position" (`nil` → giữ vị trí hiện tại hoặc append khi tạo mới) với `0`/số cụ thể (clamp về `1..n`). PATCH không kèm `position` thì không gọi `place`/không đổi position.
- **Spec:** `modules/screens/spec/services/screens/layout_service_spec.rb` — PATCH visible=false không đổi thứ tự; PATCH position=1 đưa lên đầu; item position 0 cũ không bị đẩy cuối.
- Cũng: `LayoutService.edit` bắt `ActiveRecord::RecordNotUnique` giống `replace` (trả lỗi có cấu trúc, không 500).

### T1.4 [F02] `Resolver.for_many` trả kiểu không nhất quán
- **Sửa ở:** `modules/field_rules/app/services/field_rules/resolver.rb` (~55-58, 84-90).
- **Sửa:** `for_many` luôn trả `Hash{[project_id, type_id] => config}`; cache key sentinel `[pid, :all_types]` tách sang một Set riêng (`cache[:loaded_projects]`) thay vì chung hash với key cặp. `Resolver.for` đọc từ hash cặp.
- **Spec:** `resolver_spec.rb` — `for_many([p1,p2])` và `for_many([p1],[t1])` đều trả Hash; không còn `nil`/array.

### T1.5 [F02] `project_field_rules_api` dùng `Type.find` toàn cục
- **Sửa ở:** `modules/field_rules/lib/api/v3/field_rules/project_field_rules_api.rb:32`.
- **Sửa:** `@project.types.find` (hoặc `enabled_types`, theo như `modules/screens/lib/api/v3/screens/project_screens_api.rb:49`); không tìm thấy → 404.
- **Spec:** `field_rules_api_spec.rb` — type không bật ở project ⇒ 404.

---

## Pha 2 — Bảo mật & chính sách đọc (D1)

### T2.1 Thống nhất chính sách đọc ở 3 module
- **Sửa ở:**
  - F02: `modules/field_rules/lib/api/v3/field_rules/input_helpers.rb:~39` (`authorize_rule_reading`), `field_rule_sets_api.rb`, `field_rule_schemes_api.rb`.
  - F03: `modules/screens/lib/api/v3/screens/input_helpers.rb:~39-41` (`authorize_screens_read!`), `screens_api.rb`, `screen_schemes_api.rb`.
  - F01 tham chiếu: `modules/type_schemes/lib/api/v3/type_schemes/type_schemes_api.rb` (`visible_schemes`).
- **Sửa:**
  1. Bỏ `allowed_in_any_project?(:view_work_packages)` (cho phép anonymous ở project public). Dùng `User.current.logged?` làm điều kiện tối thiểu.
  2. Thêm scope `visible_to(user)` trên model/service: admin ⇒ `all`; user khác ⇒ bản ghi được gán cho project có `view_work_packages` (qua bảng assignment `project_*_schemes` + item/rule_set/screen thuộc các scheme đó); `show` ngoài tập này ⇒ 404 (không 403, để không lộ tồn tại).
  3. Dùng chung một helper nếu giống nhau (vd. đặt trong `Projects`-scope pattern của F01) — **không** tạo abstraction mới ngoài 3 module nếu không cần; copy pattern `visible_schemes` là đủ.
  4. Resolver endpoint theo project giữ nguyên (`view_work_packages` ở project đó).
- **Spec:** mỗi module — anonymous ⇒ 401; user không có quyền ⇒ list rỗng/404; user có quyền ở project dùng scheme ⇒ thấy đúng bản ghi; admin ⇒ tất cả. Cập nhật spec "reading" cũ đã sửa ở lần trước.

### T2.2 `Resolver.system_actor?` coi `user.nil?` là system
- **Sửa ở:** `modules/field_rules/app/services/field_rules/resolver.rb:~80`; nơi dùng: `validator.rb:37`, `contract_patch.rb:57`, `schema_patch.rb:62`.
- **Sửa:** chỉ `user.is_a?(SystemUser)` mới là system; `nil` ⇒ **áp rule** (an toàn mặc định) hoặc raise rõ ràng. Kiểm tra caller: không có path hợp lệ dựng contract với `user=nil`.
- **Spec:** user nil ⇒ không bypass rule.

### T2.3 Copy project bỏ qua rule — ghi nhận, kiểm quyền
- **Sửa ở:** `modules/field_rules/lib/open_project/field_rules/contract_patch.rb:~37,203`.
- **Sửa:** chỉ comment/docs (đã có). Thêm spec: người copy không có quyền ghi field read-only vẫn không ghi được qua đường khác (contract thường). Không đổi hành vi.

---

## Pha 3 — Độ bền, hiệu năng, fail-open

### T3.1 [F01] Cache reset theo `after_commit`, bao cả cascade
- **Sửa ở:** `modules/type_schemes/app/models/type_scheme.rb:~34` (+ các model item/assignment), `modules/field_rules/app/models/field_rule.rb:~45` (+ rule_set/scheme/assignment), `modules/screens/app/models/screen.rb:~51` (+ section/item/scheme/assignment).
- **Sửa:** đổi `after_save/after_destroy → Resolver.reset_cache` thành `after_commit` (hoặc thêm `after_rollback`). Các thao tác `delete_all`/FK cascade (`type_schemes/db/migrate/20261002100000_create_type_schemes.rb:44`) không chạy callback ⇒ nơi nào dùng `delete_all` thì gọi `reset_cache` tường minh.
- **Spec:** reset sau commit; rollback transaction không để lại cache sai (`RequestStore`).

### T3.2 [F01] Memo `allowed_types`
- **Sửa ở:** `modules/type_schemes/app/services/type_schemes/resolver.rb:70-78`.
- **Sửa:** memo kết quả theo project trong `RequestStore` (cùng cache với `for_project`); `disjoint?` dùng lại kết quả đó.

### T3.3 [F03] `Screens::Resolver.for_many` còn ~5N query
- **Sửa ở:** `modules/screens/app/services/screens/resolver.rb:79-93, 136-150`.
- **Sửa:** `for_many` preload hàng loạt: `ProjectType` (1 query theo `project_id IN`), assignment scheme (1 query), `ScreenSchemeItem` (theo `scheme_id IN` + `type_id IN`), `Screen.includes(sections: :items)` (1 query theo `id IN`); gọi `Fields.availability` một lần/ cặp (project,type). Dựng kết quả từ dữ liệu đã nạp, không gọi `self.for` trong vòng lặp. Giữ `matrix` nguyên.
- **Spec:** `modules/screens/spec/services/screens/resolver_spec.rb` dùng `spec/support/query_counter.rb` — N key ⇒ số query ≤ hằng (không tuyến tính theo N).

### T3.4 Fail-open có thể quan sát (D3)
- **Sửa ở:** `modules/type_schemes/lib/open_project/type_schemes/contract_patch.rb:63-70`; `modules/field_rules/lib/open_project/field_rules/contract_patch.rb:60-62,73-75`, `validator.rb:59`, `constraints.rb:58`; `modules/screens/app/services/screens/coverage_validation.rb:~105` (rescue trả `[]` không log); các `rescue StandardError` còn lại (grep `rescue StandardError` trong 3 module, ~22 chỗ).
- **Sửa:** tạo một helper nhỏ trong mỗi module (vd. `FieldRules.fail_open(context) { ... }`) log `error` kèm class lỗi, message, project/type id, và `OpenProject.logger`/`Rails.error.report` (nếu core dùng) — **không** nuốt im lặng. Hành vi trả về giữ nguyên (fail-open). Không rescue rộng hơn mức hiện có.
- **Spec:** mở rộng `safety_fallbacks_spec`/`patches_fail_open_spec`: lỗi ⇒ hành vi cũ + có log error đúng nội dung.

### T3.5 [F02] N+1 ở representer & view
- **Sửa ở:** `modules/field_rules/lib/api/v3/field_rules/field_rule_set_representer.rb` (`rules`, `unavailable_project_counts`), `modules/field_rules/app/services/field_rules/fields.rb`, `modules/field_rules/app/views/projects/settings/field_rule_scheme/show.html.erb` (gọi `describe` mỗi type).
- **Sửa:** tính `unavailable_project_counts` một lần cho cả collection (nhận danh sách key, trả Hash, memo theo request); trong view, preload `describe` cho tất cả type một lần.
- **Spec:** query-limit trên GET list rule sets.

### T3.6 [F01/F02] Khớp lock/prepend với core
- **Sửa ở:** `modules/type_schemes/lib/open_project/type_schemes/engine.rb:~101` (`Type.after_create_commit` trong `to_prepare` bị đăng ký lặp), `modules/field_rules/lib/open_project/field_rules.rb:41-50` (`assert_patch_targets!`).
- **Sửa:** (a) đăng ký `after_create_commit` một lần (guard bằng `unless Type._commit_callbacks.any?{...}` hoặc chuyển sang `Rails.application.config.after_initialize`/hook `OpenProject::Notifications`); (b) `assert_patch_targets!` kiểm thêm `arity`/`parameters` của các private method bị override (`validate_enabled_type`, `assign_default_type`, `update_derivable_date_attribute`…); sai ⇒ log error lúc boot (không raise).
- **Chú ý:** hai module cùng override `validate_enabled_type` — ghi chú thứ tự `super` trong comment và thêm spec: cả hai bật, Type ngoài scheme *và* field rule vẫn đều có hiệu lực.

### T3.7 Dọn code thừa (nhỏ, an toàn)
- Xoá guard `defined?(RequestStore)` ở `modules/screens/app/services/screens/fields.rb:90,103,127` và `resolver.rb:126`.
- Gom `defined?(::FieldRules::Resolver)` (lặp ở `coverage_validation.rb:94`, `required_set.rb:109,152`, `resolver.rb:127,251`) vào **một** predicate `Screens::RequiredSet.field_rules?`; giữ guard (module vẫn có thể bị gỡ khỏi `Gemfile.modules`) nhưng không lặp 5 chỗ.
- **Không** gộp `scheme_service.rb`/`repair.rb` giữa 3 module (chưa cần abstraction).

---

## Pha 4 — Tài liệu & API

### T4.1 OpenAPI cho screens (sections/items)
- **Thêm:** `docs/api/apiv3/paths/screen_sections.yml`, `screen_section.yml`, `screen_items.yml`, `screen_item.yml`; đăng ký trong `docs/api/apiv3/openapi-spec.yml` (cạnh dòng ~410-431).
- **Nội dung theo code:** `modules/screens/lib/api/v3/screens/screens_api.rb` — `POST /screens/{id}/sections` (:160), `PATCH|DELETE .../sections/{sid}` (:175, DELETE 204 :193), `POST .../items` (:198), `PATCH|DELETE .../items/{iid}` (:223, DELETE 204 :253); lỗi 403/404/409(ETag)/422 (`required_not_placed`, `hidden_and_required`).
- Kiểm `docs/api/apiv3/paths/screen_scheme.yml` có PATCH (`screen_schemes_api.rb:116`).

### T4.2 Trường/header/mã lỗi mới
- Ghi vào schema docs: `requiredButEmpty` (work package schema property, `modules/field_rules/lib/open_project/field_rules/schema_patch.rb:~94`); `warnings` + tham số `warn` (`screen_representer.rb:~45`, `screens_api.rb:45-47`); header `X-Type-Scheme-Warning: no_enabled_types` (`project_type_scheme_api.rb:~55`) — docs `project_type_scheme.yml`; `unavailable` ở layout (`screen_layout_representer.rb:~95`); `unavailableInProjects` đã có ở `field_rule_set_model.yml:48`.
- Thêm GET vào `project_type_scheme.yml` (code có GET, quyền `view_work_packages`); `project_field_rule_scheme.yml` chỉ PUT là đúng — ghi rõ.
- Activate/deactivate: `screen_activate.yml`, `screen_scheme_activate.yml` thêm 401/422; ghi chú rằng type scheme và field rule dùng PATCH `active`.
- GET list/item docs của 3 module: cập nhật theo **D1/T2.1** (401/404, quyền) — `type_schemes.yml:8` hiện sai ("Requires an authenticated user"); `field_rule_set.yml`, `field_rule_scheme.yml` (GET một item) bổ sung permission.

### T4.3 Specs/idea docs
- `docs/superpowers/specs/2026-10-03-field-rules-design.md`: thêm grandfather warning (`requiredButEmpty`), `unavailableInProjects`, endpoint resolved gộp Layer 0 (`source: rule_set|native|both`), quyền đọc theo D1; làm rõ `manage_field_rules` là admin-only (không phải permission thật).
- `docs/superpowers/specs/*`: thêm mục **Rollout/feature flag** (toggle D2, cách bật), **Bảng mã lỗi chuẩn hoá** dùng chung (`not_in_scheme`, `required_not_placed`, `hidden_and_required`, `context_mismatch`, `in_use`, `invalid_context`), và **404 vs 403** thống nhất (404 khi không thấy bản ghi).
- `docs/ideas/idea-01.md` (:14, :247-333): ghi chú đầu mục rằng tên `jira_*` là ý tưởng ban đầu, bảng thật là `type_schemes*` (xem spec 2026-10-02). Không xoá nội dung gốc (giữ truy vết, như idea-02 §0).
- i18n: chạy `i18n-tasks` / so khớp key dùng vs định nghĩa cho 3 `config/locales/en.yml` (54/76/71 key được dùng), thêm key thiếu, xoá key mồ côi.

---

## Pha 5 — Test

| Task | File | Việc |
|---|---|---|
| T5.1 | `modules/type_schemes/spec/db/seed_rollback_spec.rb` | Đổi tên thành `create_type_schemes_rollback_spec.rb`; thêm spec thật cho `down` của `SeedDefaultTypeScheme` (`db/migrate/20261003100000_seed_default_type_scheme.rb`): xoá đúng Default Scheme và assignment, không đụng Type/Project/WP; cân nhắc không xoá nếu admin đã chỉnh nội dung (so sánh với dữ liệu seed). Cần chạy thật vì DDL trong transaction test. |
| T5.2 | `modules/screens/spec/requests/api/v3/screens_api_spec.rb` | Sửa assertion ETag: so sánh ETag *response* trước/sau thao tác từng phần (không dùng `updated_at.iso8601` so với ETag có `W/`/dấu nháy); giữ case `PUT` với ETag cũ ⇒ 409. |
| T5.3 | `modules/screens/spec/services/screens/resolver_spec.rb` | `have_received(:availability).once` giòn: thay bằng assert kết quả + query-limit (T3.3). |
| T5.4 | `modules/field_rules/spec/services/field_rules/native_layer_spec.rb`, `.../db/invariants_spec.rb` | Giảm `allow_any_instance_of`/`instance_double(TypeVariant)`: dùng factory `type_variant` thật với `required_attributes`; race `RecordNotUnique` → test ở mức service với hai save thật (hoặc stub `save!` ở object, không `any_instance_of`). |
| T5.5 | các `spec/models/*_spec.rb` (type_schemes) | Thay `be_present` bằng assert nội dung lỗi (`errors.details`/`errors.added?`). |
| T5.6 | field_rules | Thêm test: N+1 list (T3.5), stale cache sau sửa/xoá rule trong cùng request, rollback không để lại cache (T3.1), mail handler/import (R9) đã có — kiểm lại; Backlogs `story_points` hiện `skip` nếu Backlogs không load → chạy trong CI có Backlogs. |
| T5.7 | screens | `hidden_and_required`: tạo rule F02 thật (factory) thay vì stub `RequiredSet`; feature spec cho admin UI hiển thị `warnings` (hiện chưa có UI) — nếu không làm UI thì ghi vào docs là chỉ có ở API. |

---

## Kiểm chứng cuối (làm bởi người/CI có Ruby)

```bash
bundle exec rspec modules/type_schemes/spec modules/field_rules/spec modules/screens/spec
bundle exec rubocop modules/type_schemes modules/field_rules modules/screens
bundle exec i18n-tasks missing && bundle exec i18n-tasks unused
```
Các điểm cần chú ý khi chạy lần đầu (suy luận tĩnh, chưa kiểm): `visible_schemes` dùng `arel.exists` + `.or` (nếu lỗi đổi sang `.exists?`); route `settings_admin_type_schemes_path`; `Settings::Definition.add` cho setting mới; spec `visible_schemes`/ETag/`LayoutService.edit`.

## Ma trận ưu tiên

| Pha | Rủi ro nếu bỏ | Công sức | Song song? |
|---|---|---|---|
| 1 | Bug logic runtime (toggle sai, hidden mất) | S–M | 3 module song song |
| 2 | Rò rỉ cấu hình, bypass system actor | M | theo module |
| 3 | Perf/độ bền/quan sát lỗi | M | theo module |
| 4 | Docs sai/lệch API | M | sau Pha 1–3 |
| 5 | Spec giòn/chưa đủ | M | cùng pha liên quan |
