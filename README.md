# OpenProject (bản tùy biến ETC)

[![Github Tests](https://github.com/opf/openproject/actions/workflows/test-core.yml/badge.svg?branch=dev)](https://github.com/opf/openproject/actions/workflows/test-core.yml)

Đây là bản fork của [OpenProject](https://www.openproject.org) – phần mềm quản lý dự án mã nguồn mở chạy trên nền web, dành cho các nhóm và tổ chức cần sự minh bạch, linh hoạt và quyền kiểm soát dữ liệu. Có thể tự triển khai (self-host) để thay thế các công cụ như Jira, MS Project, Monday, Asana hay YouTrack mà vẫn giữ toàn quyền với dữ liệu và hạ tầng.

## Tính năng chính

- Quản lý dự án và danh mục dự án (portfolio)
- Bảng Agile: Kanban, Scrum
- Lập kế hoạch và tiến độ với biểu đồ Gantt, lịch, team planner
- Quản lý công việc (work package), theo dõi lỗi
- Chấm công, báo cáo chi phí và ngân sách
- Wiki, diễn đàn, tin tức, tài liệu, biên bản và chương trình họp
- Tích hợp: Nextcloud, XWiki, GitHub, GitLab, LDAP, OpenID Connect, SAML…

Tài liệu đầy đủ của dự án gốc: <https://www.openproject.org/docs/>.

## Điểm khác so với bản gốc

- **Giao diện gọn, hiện đại, compact:** giảm chiều cao header, sidebar, dòng bảng; thu nhỏ nút, tab, input. Ghi đè CSS nằm ở `frontend/src/global_styles/layout/_compact.sass` và `frontend/src/global_styles/content/work_packages/_modern_compact.sass`.
- **Công tắc mật độ giao diện** (Compact / Comfortable) trên thanh header, lưu theo từng trình duyệt (`localStorage`).
- **Trang `/projects/{code}/work_packages`:**
  - Tooltip xem nhanh khi rê chuột vào dòng, hiển thị theo vị trí con trỏ.
  - Click chọn dòng, double-click mở chi tiết.
- **Module bổ sung** trong thư mục `modules/`: `issue_view` (API chỉ đọc cho giao diện xem issue), `screens`, `field_rules`, `type_schemes`, `ldap_departments`, `resource_management`… Thiết kế chi tiết nằm trong `docs/superpowers/specs/`.
- **Docker gọn theo môi trường:** local, staging, production và CI (xem bên dưới).

## Cấu trúc thư mục chính

| Thư mục | Nội dung |
|---|---|
| `app/`, `lib/`, `config/` | Backend Ruby on Rails |
| `frontend/` | Giao diện Angular, SASS toàn cục, Stimulus |
| `modules/` | Các module mở rộng (Gantt, Boards, Costs, Meeting, Storages…) |
| `extensions/op-blocknote-hocuspocus/` | Máy chủ soạn thảo cộng tác (Hocuspocus) |
| `tools/deunhealth/` | Dịch vụ phụ khởi động lại container không khỏe (tùy chọn) |
| `docker/prod/`, `docker/ci/` | Dockerfile cho production/local/staging và CI |
| `docs/` | Tài liệu, đặc tả API, kế hoạch triển khai |

## Chạy bằng Docker

Yêu cầu: Docker và Docker Compose v2. Mỗi môi trường có file compose riêng, và đều build từ mã nguồn trong repo bằng `docker/prod/Dockerfile`.

| Môi trường | File compose | File biến môi trường mẫu |
|---|---|---|
| Local (HTTP, `http://localhost:8080`) | `docker-compose.local.yml` | `.env.local.example` |
| Staging | `docker-compose.staging.yml` | `.env.staging.example` |
| Production (build từ mã nguồn) | `docker-compose.production.yml` | `.env.production.example` |
| Production (chỉ kéo image build sẵn) | `docker-compose-run-production.yaml` | `.env.production.example` |
| CI | `docker-compose.ci.yml` | – |

### Local

```bash
cp .env.local.example .env.local
# chỉnh .env.local nếu cần
docker compose --env-file .env.local -f docker-compose.local.yml up -d --build
```

Xem log và dừng:

```bash
docker compose --env-file .env.local -f docker-compose.local.yml logs -f web worker
docker compose --env-file .env.local -f docker-compose.local.yml down
```

### Staging / Production

```bash
cp .env.production.example .env.production   # staging: .env.staging.example
# điền SECRET_KEY_BASE, COLLABORATIVE_SERVER_SECRET, mật khẩu DB, tên miền…
docker compose --env-file .env.production -f docker-compose.production.yml up -d --build
```

Trên máy chủ chỉ cần kéo image đã build sẵn, dùng script `run-production.sh`:

```bash
./run-production.sh up        # pull + chạy
./run-production.sh ps        # trạng thái
./run-production.sh logs web  # xem log
./run-production.sh down      # dừng
```

> Lưu ý: không commit file `.env*` thật và không dùng lại giá trị mẫu ở môi trường công khai. Khi `web` vừa được tạo lại, chờ trạng thái `healthy` (vài chục giây) trước khi truy cập, nếu không proxy sẽ trả `502`.

## Phát triển giao diện

Giao diện nằm trong `frontend/`. Sau khi sửa SASS hoặc TypeScript cần build lại frontend (hoặc rebuild image `web`) rồi tải lại trang. Chi tiết môi trường phát triển: [hướng dẫn cho lập trình viên](https://www.openproject.org/docs/development/development-environment/).

## Đóng góp và báo lỗi

- Báo lỗi của OpenProject gốc: <https://www.openproject.org/docs/development/report-a-bug/>.
- Với thay đổi riêng của bản ETC, hãy tạo issue hoặc merge request trong repo này.

## Bảo mật

Nếu phát hiện lỗ hổng bảo mật, vui lòng báo riêng tư thay vì công khai. Xem hướng dẫn tại [docs/security-and-privacy/statement-on-security/README.md](docs/security-and-privacy/statement-on-security/README.md).

## Giấy phép

OpenProject được cấp phép theo GNU General Public License phiên bản 3. Xem chi tiết trong các file [COPYRIGHT](COPYRIGHT) và [LICENSE](LICENSE).

## Ghi công

### Biểu tượng

Cảm ơn Vincent Le Moign và bộ biểu tượng Minicons trên [webalys.com](http://www.webalys.com/minicons/icons-free-pack.php).

### Font biểu tượng OpenProject

Được xuất bản bởi OpenProject Foundation (OPF) theo giấy phép [Creative Commons Attribution 3.0 Unported](http://creativecommons.org/licenses/by/3.0/), với biểu tượng từ
[Minicons Free Vector Icons Pack](http://www.webalys.com/minicons) và
[User Interface Design framework](http://www.webalys.com/design-interface-application-framework.php) của webalys.

Font được dùng miễn phí cho cả mục đích cá nhân và thương mại; có thể sao chép, chỉnh sửa, phân phối, với điều kiện ghi nhận "OpenProject Foundation" và liên kết về [www.openproject.org](https://www.openproject.org).
