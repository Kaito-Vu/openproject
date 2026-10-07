# Issue View — Pre-flight & deviations (Task 0)

Môi trường: không có Ruby/Postgres ⇒ **không chạy được** RSpec/rubocop. Mọi điểm dưới đây xác minh bằng code inspection (file:line trong spec §1); trạng thái test: **UNVERIFIED (not run)**.

## Điểm tựa core (PASS theo code inspection)

`WorkPackage#display_id` · `Journal#render_detail` · `Relation.visible` (+ `wp.relations.visible`) · `WorkPackageRepresenter` · `Schema::SpecificWorkPackageSchema#assignable_statuses` / `Schema::WorkPackageSchemaRepresenter` · `API::V3::Activities::ActivityPropertyFormatters` · `API::Errors::InvalidQuery` · `add_api_endpoint` (costs engine mẫu) · `PropertyNameConverter.from_ar_name`.

## Quyết định (Task 0)

| # | Quyết định |
|---|---|
| (a) Quyền | Dựng **một** `WorkPackageRepresenter` (`embed_links: false`) và đọc `_links` (cùng nguồn với native; không rải `allowed_to?`). `transition` = `edit` ∧ `schema.assignable_statuses` có status khác hiện tại. Query-count test đảm bảo không tăng theo số field. |
| (b) Feature flag Q-G | F03 **không có** flag (spec F03 "Rollout"). F04 theo đó: **không flag runtime**; tắt = gỡ dòng khỏi `Gemfile.modules`. Task 13 bỏ. |
| (c) Schema | `SpecificWorkPackageSchema` + `WorkPackageSchemaRepresenter.create(form_embedded: true)` → JSON: `type`, `writable`, `name`, `_attributeGroups` (nguồn `dataType`, `editable`, layout native). Giá trị lấy từ JSON của `WorkPackageRepresenter` (không tự đoán). |

## Lệch so với spec (ghi nhận)

1. Section `id` của layout **native** = chỉ số (1-based, chuỗi) — JSON schema chỉ có tên group đã dịch, không có key group.
2. `actor` của event chưa có `_links.avatar`; `comment` chưa có link `update` (cả hai là bổ sung nhỏ, không ảnh hưởng hợp đồng cốt lõi).
3. Lọc `type` khác `COMMENT`-thuần: lọc **trong bộ nhớ** trên toàn bộ journal visible rồi phân trang (đúng ngữ nghĩa Q-I nhưng O(số journal)); `COMMENT`-thuần lọc SQL. Ceiling đã biết.
4. Chưa có `en.yml` (module không có chuỗi UI/lỗi riêng; lỗi dùng `api_v3.errors.missing_or_malformed_parameter` của core). Thêm khi có chuỗi mới.
5. Chưa có OpenAPI + contract test (Task 8, 12): làm tiếp.
6. Gemfile.lock đã thêm tay khối `PATH` + `openproject-issue_view!`; `bundle install` trên máy dev sẽ xác nhận/chỉnh.
