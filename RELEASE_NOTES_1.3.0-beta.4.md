# APLite 1.3.0 (beta 4)

**Ngày:** 24/11/2026 · **Artifact bản này:** `APLite-unsigned-1.3.0-beta.4.ipa` (chưa ký — ký bằng ESign / Feather / Scarlet / SideStore trước khi cài).

## Beta 4 — chuột không dây, Dynamic Island và audit trình duyệt
- **Chuột không dây:** `GCMouse.handlerQueue` chuyển sang `.userInteractive` cho mọi chuột đã kết nối; chuyển động và cuộn được gộp và vẽ một lần mỗi khung hình qua `CADisplayLink` chạy ở chế độ `.common` (không bị dừng khi đang scroll/kéo cửa sổ). Touchpad ảo tự tạm dừng khi có chuột thật và bật lại ngay khi rút chuột. Mouse check hiển thị độ trễ move → render và bật log timestamp từng sự kiện.
- **Dynamic Island:** pill xuất hiện khi có media đang phát (web hoặc Quick Look), mở rộng bằng spring khi nhấn giữ, hiển thị ảnh bìa, quang phổ FFT, thời lượng/tiến độ và các nút điều khiển. Nằm trong `UIWindow` overlay riêng, không làm thay đổi layout desktop; phản hồi cả chuột thật lẫn cảm ứng; ẩn mượt khi media kết thúc; ngừng phân tích khi thu gọn hoặc vào background.
- **Trình duyệt (audit):** khôi phục toàn bộ bridge trong popup đăng nhập; so khớp host web app theo tên miền con thay vì cắt 2 nhãn; dọn highlight tìm kiếm đúng tab; thoát HTML an toàn cho trang media; sửa trạng thái resume download bị kẹt; thay `css-display-none` bằng `hide-elements`; tôn trọng allow-list có đường dẫn; quảng cáo YouTube xử lý cả shadow root và `youtu.be`; fullscreen shim trả Promise; class sạch Facebook được khôi phục.
- **Tương thích:** UA lấy đúng phiên bản HĐH thực từ `ProcessInfo` (không bịa `17.0`), cập nhật ví dụ Safari 27; `build.yml` chạy trên `main`; beta được đánh dấu prerelease để update checker không nhầm là bản stable.
- **Kiểm chứng:** CI build + unit test **success** (xem run `45360200202` trên repository). Độ mượt chuột, CPU/Instruments, VoiceOver và giao diện sáng/tối **vẫn cần thử trên iPad/iPhone thật** trước khi phát hành stable.
