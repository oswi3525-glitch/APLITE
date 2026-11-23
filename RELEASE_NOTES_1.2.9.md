# APLite 1.2.9 — Bản vá lỗi

**Ngày:** 23/11/2026 · **Artifact:** `APLite-unsigned-1.2.9.ipa` (chưa ký — ký bằng ESign / Feather / Scarlet / SideStore trước khi cài).

Bản vá trên nền 1.2.8, không đổi Bundle ID, khóa lưu trữ, Guest Engine hay attribution. Tập trung vào bàn phím, quản lý cửa sổ, thông tin nhiệt và dọn Settings.

## 1. Bàn phím ảo trên màn hình ngoài
- Kéo được bằng thanh tiêu đề; vị trí được nhớ giữa các lần mở và luôn được kẹp trong màn hình hiện tại.
- Nút **−** thu nhỏ thành thanh nhỏ, **+** mở lại; nút **× ở góc** và Esc để đóng. Phím hide cũ vẫn giữ.
- Sửa lỗi phím bị đẩy ra ngoài màn hình ở cỡ lớn nhất (130%): chiều rộng giờ bị giới hạn bởi màn hình.
- Settings → Input có nút "Đặt lại vị trí bàn phím".

## 2. Nút Window trên dock
- Nút mới nằm bên trái Task Manager; click mở danh sách gọn các cửa sổ đang mở.
- Click một dòng để focus/khôi phục cửa sổ (kể cả đã thu nhỏ), × để đóng; footer có Tile và Show desktop.
- Tối đa 7 dòng được vẽ và hit-test để không chồng lên footer; các cửa sổ còn lại dùng Task Manager / Recent apps.
- Panel tự đóng khi đổi workspace, rút màn hình, khóa, Esc hoặc Back.

## 3. Nhiệt độ
- Tray và quick panel hiển thị chỉ số áp lực 0–100% kèm xu hướng ↑/↓, màu theo trạng thái.
- Technical Diagnostics ghi rõ chỉ số, thời gian ở trạng thái hiện tại, đỉnh phiên, pin/sạc và Low Power Mode.
- **iOS không có API công khai trả °C cho app bên thứ ba** — đây là chỉ số suy từ `ProcessInfo.thermalState`, không phải phép đo nhiệt độ. Sampling chậm hơn lúc mát, nhanh hơn lúc nóng; timer chạy ngay cả khi khởi động ở trạng thái nominal.

## 4. Settings gọn hơn
- Build Center/App Creator, chứng chỉ và Technical Diagnostics gom thành một trang **Advanced tools**.
- Bỏ toggle "Release caches when idle" (không có nơi đọc giá trị). **Khóa dữ liệu cũ vẫn được giữ**, không mất cài đặt khi nâng cấp.

## 5. Khắc phục từ audit
- Widget thời tiết không còn chia sẻ biến mutable giữa callback geocoding và network (dùng hộp có khóa).
- Bổ sung chuỗi tiếng Việt cho các nhóm Settings, bàn phím, cửa sổ và Advanced.
- Thêm unit test thuần cho geometry bàn phím, chỉ số nhiệt và danh sách cửa sổ.

## 6. Kiểm chứng
- Kiểm tra tĩnh tại repo: JSON/YAML parse, cân bằng cú pháp các file Swift sửa, `git diff --check`.
- Build IPA + unit test chạy trên CI macOS — CI là nguồn chân thực. **Chưa xác nhận trên thiết bị thật**; xem `SYSTEM_TEST_PLAN.md` mục 1.2.9.
- Finding còn mở từ audit: cờ `inherited` trong `DeskWindow.applyBrowserPolicy` vẫn cần thử nghiệm popup đăng nhập trên thiết bị.

APLite là dự án độc lập dựa trên iDesk gốc của itshieuk: https://github.com/itshieuk/iDesk — không phải phát hành chính thức hay được xác nhận bởi dự án gốc.
