# APLite 1.2.8 — Bản vá ổn định

**Ngày:** 23/11/2026 · **Artifact:** `APLite-unsigned-1.2.8.ipa` (chưa ký — ký bằng ESign / Feather / Scarlet / SideStore trước khi cài).

Bản vá trên nền 1.2.7, không đổi kiến trúc: sửa âm thanh, bổ sung chẩn đoán kỹ thuật trong Settings, cải thiện Settings và cửa sổ, chỉnh lại Thùng rác và zoom WebApp.

## 1. Trình duyệt / WebKit
- Một hàm cấu hình duy nhất cho tab thường **và** popup đăng nhập: UA Safari thật (lấy phiên bản từ iOS), process pool dùng chung, cờ media, script và message bridge. Popup không còn mất audio/focus bridge.
- Rule chặn quảng cáo được áp lại cho tab tạo trong lúc rule list đang biên dịch; tab OAuth không bị discard khi áp lực bộ nhớ; dọn mã tab zoom/gamepad cũ; tải lại download tạm dừng không còn dùng tab khác origin.
- **Giới hạn nền tảng (BLOCKED, không tuyên bố hỗ trợ):** engine Chrome/Chromium, Service Worker (cần entitlement), WebAuthn/passkeys trong WKWebView nhúng, đọc log/tiến trình khác. Không giả UA, không giấu banner của Google.

## 2. Âm thanh
- Popup web thừa kế cấu hình media; guest app đang phát không bị cắt khi thu nhỏ/chuyển workspace; thay đổi category của guest được khôi phục; voice typing dừng sạch khi bị ngắt; JS không còn giữ media element; ô "Mute" đổi thành "Volume zero" (iOS không có API đọc công tắc im lặng phần cứng).

## 3. Technical Diagnostics (mới)
- Đường dẫn duy nhất: **Settings → System → Technical Diagnostics**. Không có icon desktop/dock/launcher, không tạo app hay scene mới, không chạy nền liên tục.
- Chỉ đọc dữ liệu APLite đang có: browser, audio, cửa sổ, RAM, trạng thái nhiệt, độ trễ main thread (chỉ đo khi mở màn hình), lịch sử lỗi; đưa nguyên nhân có thể và sửa chữa an toàn sau xác nhận, rồi kiểm tra lại. Không tuyên bố đọc CPU từng app hay log iOS.

## 4. Settings & cửa sổ
- Section có icon, danh sách inset-grouped, kiểu chữ/chú thích thống nhất; cho phép Settings theo hệ thống / sáng / tối trên iPhone; xác nhận trước thao tác nguy hiểm. Mọi giá trị đã lưu được giữ nguyên.
- Chrome cửa sổ dùng một bảng màu; fullscreen/tối đa animate đúng; nút exit PiP; huy hiệu pin không chèn vào tab; WebApp có nút − / % / + trên title bar, mức 100% lưu ổn định.

## 5. Thùng rác
- Guest app đóng gói chỉ được **đánh dấu xóa** (cần ký lại + cài lại), kéo hai lần không hủy đánh dấu; không thể ẩn icon Trash; có thể khôi phục WebApp vừa xóa từ menu desktop. Không bao giờ tuyên bố gỡ app iOS/App Store.

## 6. Kiểm chứng
- Tree-sitter Swift, JSON/YAML, `node --check` JS nhúng; unit test CI ( macOS ) — xem báo cáo release. Chưa xác nhận trên thiết bị thật; xem `SYSTEM_TEST_PLAN.md` mục 1.2.8.

APLite là dự án độc lập dựa trên iDesk gốc của itshieuk: https://github.com/itshieuk/iDesk — không phải phát hành chính thức hay được xác nhận bởi dự án gốc.
