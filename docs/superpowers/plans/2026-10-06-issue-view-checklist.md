# Issue View — Task Checklist

Plan: [2026-10-06-issue-view.md](2026-10-06-issue-view.md) · Spec: [../specs/2026-10-06-issue-view-design.md](../specs/2026-10-06-issue-view-design.md) · Idea: [idea-04](../../ideas/idea-04.md)

> Ghi vào mỗi task khối **Verification**: lệnh, exit status, số pass/fail dán nguyên văn. Chưa chạy ⇒ `UNVERIFIED (not run)` và commit `[unverified]`. Không viết "pass" nếu chưa chạy.

## Lát 1

- [x] **Task 0 — Pre-flight + cổng dừng** · Verification: UNVERIFIED (not run)
- [x] **Task 1 — Skeleton module + mount rỗng** · Verification: UNVERIFIED (not run)
- [x] **Task 2 — Support: query counter, factories, authz helper** · Verification: UNVERIFIED (not run)
- [x] **Task 3 — `Permissions`** · Verification: UNVERIFIED (not run)
- [x] **Task 4 — `Counts` (+ parent)** · Verification: UNVERIFIED (not run)
- [x] **Task 5 — `Values` (dataType, value, editable)** · Verification: UNVERIFIED (not run)
- [x] **Task 6 — `Layout` (F03/native/fail-open/diagnostics)** · Verification: UNVERIFIED (not run)
- [x] **Task 7 — `Builder` + representer + endpoint `issue_view` + authz + query-count** · Verification: UNVERIFIED (not run)
- [x] **Task 8 — OpenAPI (`issue_view`)** · paths + openapi-spec.yml xong; schema model & contract test **chưa** · Verification: UNVERIFIED (not run)

## Lát 2

- [x] **Task 9 — `ActivityNormalizer`** · Verification: UNVERIFIED (not run)
- [x] **Task 10 — Tham số phân trang/sort/filter (rescue JSON hỏng)** · Verification: UNVERIFIED (not run)
- [x] **Task 11 — Representer + endpoint `activities`** · Verification: UNVERIFIED (not run)
- [x] **Task 12 — Leak/authz + OpenAPI (`activities`)** · query-count activities & contract test **chưa** · Verification: UNVERIFIED (not run)

## Lát 3

- [-] **Task 13 — Feature flag (Q-G)** · Verification: DROPPED: F03 không có flag (preflight (b))
- [x] **Task 14 — Bất biến toàn module (chỉ GET, không "jira", i18n, copyright)** · Verification: UNVERIFIED (not run)
- [ ] **Task 15 — Kiểm toàn bộ + bàn giao** · cần chạy rspec/rubocop trên máy dev

## Truy vết spec §12 → task

| Kịch bản | Task | | Kịch bản | Task |
|---|---|---|---|---|
| 1–2 | 6, 7 | | 15–16 | 9 |
| 3 | 6 | | 17 | 12 |
| 4–5 | 7 | | 18 | 10, 11 |
| 6–7 | 5 | | 19 | 12 |
| 8–10 | 3, 5, 7 | | 20 | 7, 12 |
| 11, 14 | 4 | | 21 | 14 |
| 12 | 7 | | 22 | 7, 12 |
| 13 | 6 | | 23 | 7 |
| | | | 24 | 14 |
| | | | 25 | 13 |
