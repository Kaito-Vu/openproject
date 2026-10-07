# Chính sách bảo mật (Security Policy)

Chúng tôi coi bảo mật là ưu tiên hàng đầu và trân trọng mọi phản hồi giúp giữ an toàn cho người dùng và cộng đồng. Vui lòng **không công khai** lỗ hổng bảo mật qua issue, pull request hay thảo luận công khai; hãy báo riêng tư theo hướng dẫn dưới đây.

## Phiên bản được hỗ trợ

Repository này là bản fork của [OpenProject](https://github.com/opf/openproject) (nhánh phát triển `dev`).

| Phiên bản / nhánh | Hỗ trợ bản vá bảo mật |
|---|---|
| `dev` (bản tùy biến của repo này) | ✅ |
| Các nhánh/tag cũ hơn của repo này | ❌ |
| Bản phát hành chính thức của OpenProject (upstream) | Theo [chính sách của OpenProject](https://www.openproject.org/docs/security-and-privacy/statement-on-security/) |

Lỗ hổng nằm trong **mã gốc của OpenProject** (không do phần tùy biến của repo này) sẽ được sửa ở upstream và đồng bộ về đây.

## Cách báo cáo lỗ hổng

### 1. Lỗ hổng trong phần tùy biến của repo này

Dùng **GitHub Private Vulnerability Reporting**:

> [Báo cáo lỗ hổng riêng tư](https://github.com/Kaito-Vu/openproject/security/advisories/new) (tab **Security → Report a vulnerability**).

Báo cáo ở dạng riêng tư sẽ chỉ hiển thị với người báo cáo và nhóm bảo trì cho đến khi được công bố.

Nếu không dùng được GitHub, gửi email tới: **`<TODO: điền email liên hệ bảo mật của nhóm>`**.

### 2. Lỗ hổng trong OpenProject gốc

Báo trực tiếp cho đội bảo mật của OpenProject:

- Email: [security@openproject.com](mailto:security@openproject.com) (khuyến nghị mã hóa PGP, Key ID `0x7D669C6D47533958`).
- Hoặc [GitHub Security Advisory của upstream](https://github.com/opf/openproject/security/advisories/new).

Tham khảo thêm: [Statement on security](docs/security-and-privacy/statement-on-security/README.md).

## Thông tin nên có trong báo cáo

Càng đầy đủ, chúng tôi càng xử lý nhanh:

- Mô tả lỗ hổng và loại (ví dụ XSS, SQL injection, SSRF, bypass phân quyền, lộ dữ liệu).
- Thành phần và phiên bản/commit bị ảnh hưởng.
- Các bước tái hiện, hoặc mã/ảnh chụp/video minh họa (PoC).
- Tác động dự kiến và điều kiện khai thác (có cần đăng nhập, quyền gì).
- Gợi ý cách khắc phục (nếu có).

**Không** gửi dữ liệu thật của người dùng, mật khẩu, token hay khóa bí mật trong báo cáo.

## Quy trình xử lý và thời gian dự kiến

Các mốc dưới đây là **mục tiêu**, thời gian thực tế phụ thuộc vào độ phức tạp:

| Bước | Mục tiêu |
|---|---|
| Xác nhận đã nhận báo cáo | trong 3 ngày làm việc |
| Đánh giá, phân loại mức độ nghiêm trọng | trong 7 ngày |
| Bản vá cho lỗ hổng mức Critical/High | trong 21 ngày kể từ khi xác nhận |
| Công bố advisory sau khi có bản vá | phối hợp với người báo cáo |

Một lỗ hổng chỉ được coi là đã sửa khi bản vá đã được phát hành cho tất cả phiên bản được hỗ trợ bị ảnh hưởng. Chúng tôi sẽ thông báo tiến độ cho người báo cáo trong suốt quá trình.

## Phạm vi

**Trong phạm vi:**

- Mã nguồn trong repository này (backend Rails, frontend, các module trong `modules/`).
- Cấu hình và image Docker (`docker/`, `docker-compose*.yml`, `extensions/`, `tools/`).

**Ngoài phạm vi:**

- Tấn công từ chối dịch vụ (DoS/DDoS) khối lượng lớn, spam, tấn công vật lý.
- Kỹ thuật xã hội (social engineering) nhằm vào nhân sự.
- Lỗi trong dịch vụ hoặc phần mềm của bên thứ ba (hãy báo cho chủ sở hữu tương ứng).
- Báo cáo từ công cụ quét tự động không có bằng chứng khai thác.
- Cấu hình yếu ở hệ thống của người dùng triển khai (ví dụ để nguyên mật khẩu mẫu trong `.env*.example`).

## Nghiên cứu an toàn (Safe harbor)

Chúng tôi sẽ không theo đuổi hành động pháp lý đối với nghiên cứu bảo mật thiện chí tuân theo chính sách này. Khi kiểm thử, vui lòng:

- Chỉ thử trên **hệ thống do bạn sở hữu hoặc môi trường thử nghiệm**, không tác động đến dữ liệu, tài khoản hay dịch vụ của người dùng khác.
- Dừng ngay khi đã chứng minh được lỗ hổng, không khai thác sâu hơn và không trích xuất dữ liệu ngoài mức cần thiết.
- Không công bố chi tiết lỗ hổng trước khi có bản vá và thống nhất thời điểm công bố với chúng tôi.

## Công nhận đóng góp

Với báo cáo hợp lệ, chúng tôi sẽ ghi nhận người báo cáo trong advisory (trừ khi bạn muốn ẩn danh).

## Giữ an toàn khi triển khai

- Không commit `.env*` thật; đặt `SECRET_KEY_BASE`, `COLLABORATIVE_SERVER_SECRET`, mật khẩu DB riêng cho từng môi trường.
- Không dùng giá trị mặc định trong file compose ở môi trường công khai.
- Cập nhật thường xuyên để nhận bản vá bảo mật.

Chi tiết về quy ước an toàn cho lập trình viên: [WIKI.md](WIKI.md#8-safety-an-toàn-và-bảo-mật).
