# APLite 1.2.7 — System overhaul maintenance release

**Ngày:** 23/11/2026 · **Artifact:** `APLite-unsigned-1.2.7.ipa` (chưa ký — ký bằng ESign / Feather / Scarlet / SideStore trước khi cài).

Bản vá kỹ thuật trên nền kiến trúc 1.2.6: nâng khả năng tương thích trình duyệt, chuẩn hóa màu, thêm quản lý ứng dụng bằng kéo vào Thùng rác, zoom riêng cho từng WebApp và dọn thương hiệu iDesk còn sót lại. **Không đổi Bundle ID, khóa lưu trữ, Guest Engine hay giấy phép gốc.**

## 1. Trình duyệt / Gmail
- Nguyên nhân thông báo "This browser version is no longer supported": chế độ desktop của WKWebView tạo UA **không có** token `Version/… Safari/…`, nên Google xem đây là trình duyệt không xác định/lỗi thời.
- Sửa bằng `applicationNameForUserAgent` chứa **đúng phiên bản Safari lấy từ iOS** — WebKit vẫn tự tạo token `AppleWebKit/605.1.15`; không giả Chrome, không giấu thông báo, không tắt bảo mật.
- Popup đăng nhập được áp lại cùng UA + `preferredContentMode = .desktop`; dùng chung một `WKProcessPool`.
- WebContent bị iOS giết: tab tự reload **một lần**; tab `accounts.google.com` không bị discard khi áp lực bộ nhớ.

## 2. Màu sắc
- `APLiteColors`: màu sRGB cố định. `#FF0000` khai báo là đỏ thì hiển thị đỏ — không bị systemRed ở chế độ tối hay alpha-over-glass biến thành hồng.
- CSS danger (`#ff8a80`, `#ff6961`) được thống nhất thành `#ff0000`; icon hue-based dùng `colorSpace: .sRGB`; clamp chuyển Color→CSS; manifest từ xa không được đưa accent đỏ hồng vào toàn giao diện.

## 3. Quản lý ứng dụng & Thùng rác
- Kéo icon trên desktop/Launcher vào Trash: WebApp được gỡ cùng pin/recents/slot/cửa sổ; guest app import được xóa sau khi đóng cửa sổ; guest app đóng gói chỉ được **đánh dấu** (cần ký lại + cài lại APLite); file desktop đi vào Thùng rác của Files; trang hệ thống bị từ chối.
- Có highlight khi kéo vào Trash và mục "Uninstall" trong menu chuột phải.
- **iOS không cho phép một app gỡ app khác** — APLite không bao giờ giả vờ làm được điều này.

## 4. Zoom WebApp
- 9 mức thống nhất: 50 / 75 / 90 / 100 / 110 / 125 / 150 / 175 / 200%.
- Dùng API chính thức `WKWebView.pageZoom` (có từ iOS 14) thay vì chèn CSS zoom mỗi lần tải trang; không chồng 2 cơ chế.
- Lưu riêng từng WebApp theo định danh cài đặt (chống redirect), áp cho cả tab popup, ⌘0 về 100%.

## 5. Thương hiệu & hiệu năng
- Sửa 5 điểm hiển thị còn sót iDesk (issue template, thông báo lỗi guest, token dlopen, tên IPA xuất, comment/.gitignore). Giữ nguyên LICENSE/NOTICE/ghi nhận itshieuk và mọi định danh tương thích.
- Bỏ render lại toàn desktop khi kéo widget, chỉ publish giá trị bộ nhớ thay đổi, gộp refresh Settings, dọn observer guest, sửa URL tải xuống dự phòng của trình kiểm tra cập nhật.
- CI release: chọn Xcode rõ ràng và chạy toàn bộ unit test trước khi phát hành.

## 6. Kiểm chứng
- Static: tree-sitter Swift, JSON/YAML, `node --check` cho JS nhúng. Unit test mới: UA builder, zoom math, color parser, trash policy.
- Build IPA + unit test trên macOS GitHub Actions. **Chưa xác nhận trên thiết bị thật** — xem `SYSTEM_TEST_PLAN.md` mục 1.2.7.

APLite là dự án độc lập dựa trên iDesk gốc của itshieuk: https://github.com/itshieuk/iDesk — không phải phát hành chính thức hay được xác nhận bởi dự án gốc.
