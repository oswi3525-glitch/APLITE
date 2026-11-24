# APLite 1.3.0 (beta 2)

**Ngày:** 24/11/2026 · **Artifact bản này:** `APLite-unsigned-1.3.0-beta.2.ipa` (chưa ký — ký bằng ESign / Feather / Scarlet / SideStore trước khi cài).

## Beta 2 — audit toàn repo và vá bảo mật
- **Bảo mật:** redact crash report trước khi đưa vào GitHub issue công khai; mở rộng redaction (JSON, Bearer, `api_key`, `pin`, `session`); Data Protection cho kho cookie, log và export khảo sát; Keychain ký dùng `WhenUnlockedThisDeviceOnly` + migration; chặn `CFBundleExecutable` path traversal; Unzip chặn prefix/overflow; bridge Files kiểm tra main frame; BuildCenter chỉ gửi Bearer tới host GitHub và bỏ Authorization khi redirect khác host; ghi chú khảo sát được redact.
- **Sửa lỗi:** khảo sát chuyển sang phone surface (màn hình ngoài không nhận kéo thả); quét dọn rác và đọc log ra luồng nền; cài đặt **Auto-lock after có tác dụng**; `APLiteSettings.bool` không còn ép số thành `true`; không xoá icon web app khi registry lỗi; không xoá cache WebKit.
- **Phát hành:** mặc định build HEAD là stable (kênh trống); beta chỉ bật khi release input đặt `beta 2`. Workflow dùng `MARKETING_VERSION=1.3.0` nên trong app hiển thị đúng **1.3.0 (beta 2)**. So sánh phiên bản không còn xếp beta trên stable. Thêm justification monospace cho 5 file keycap/code, token hoá LockScreen, nhãn nút xác nhận rõ hành động, 16 khoá tiếng Việt bổ sung.
- **Kiểm chứng:** CI `45307515029` build + unit test **success**. Chi tiết: `AUDIT_FULL_REPO_1.3.0.md`.

---

# APLite 1.3.0 (beta 1) — bản gốc

Bản beta đầu tiên của 1.3.0. Không đổi Bundle ID, khóa lưu trữ (kể cả `iDesk.*` cũ), Guest Engine hay attribution. Gói kênh phát hành `beta 1` bật tính năng chỉ dành cho beta; bản stable cùng mã nguồn để kênh trống và ẩn các tính năng này hoàn toàn.

## 1. Sửa lỗi treo màn hình khởi động (ưu tiên cao nhất)
- Watchdog 20s không còn nằm cùng main queue với công việc nó giám sát: khi một bước block main, watchdog vẫn ghi `fault` có timestamp từ luồng nền, rồi mới quay về main để hiện giao diện retry cũ.
- Callback audio không còn kéo `DesktopModel.shared` (quét app khách, đọc Keychain, đo thư mục) vào boot step 2. Trước khi boot xong vốn không có cửa sổ/tab nào để kiểm tra.
- Cờ legacy `iDesk.clearCachesOnLaunch` — nguyên nhân xoá đồng bộ hàng GB cache trên main sau khi nâng cấp — giờ được xử lý trong sweep nền.
- Chế độ preview tự đóng overlay boot; trước đây overlay desktop không bao giờ tắt khi không có màn hình ngoài.
- Mỗi giai đoạn boot được log kèm thời gian `Boot step … in N ms`. Không dùng delay giả; không khởi động lại hệ thống khi từ background lên foreground.

## 2. Nhật ký hệ thống
- Ghi song song Apple Unified Logging (`os_log`) và một tệp JSONL có giới hạn trong sandbox APLite.
- Bốn mức: info, debug, error, fault — có timestamp, tên module, mô tả đã redaction.
- Xem / lọc / xoá tại **Cài đặt → Quyền riêng tư & Bảo mật → Nhật ký hệ thống**. Tồn tại qua các lần khởi động lại; rotate ở 512 KB, tối đa 2 bản cũ.
- **Không** dùng private API `OSLogStore`, không đọc log của tiến trình/app khác.

## 3. Cài đặt 5 tab
- **Hệ thống / Ứng dụng / Quyền riêng tư & Bảo mật / Dọn rác & Tối ưu / APStore.**
- Tab Hệ thống chính là `SystemSettingsView` cũ, giữ nguyên 100% điều khiển, khóa và hành vi. Bốn tab còn lại chỉ bổ sung tính năng mới.
- Desktop HTML Settings chưa tab hoá để tránh rủi ro bridge/JS khi chưa có build để kiểm chứng.

## 4. APStore
- Phân biệt rõ **Web Apps** (lối tắt website, cài qua `WebApps.install`) và **Native Modules** (mã được ký cùng APLite, quản lý qua `GuestStore`).
- Kiểm tra toàn vẹn bằng SHA-256 trước khi tin dùng module.
- **APLite không cài được IPA tuỳ ý từ bên ngoài** — iOS cấm do ràng buộc chữ ký và sandbox. Kho này không có gói `.aplite`, nên không bịa ra định dạng hoặc hứa hẹn sai.

## 5. Dọn rác & bảo mật
- Quét/xoá trong sandbox: cache của app khách, tệp tạm (`export-`, `update-`, `cert-`, `aplite-app-`), log xoay, diagnostics cũ, archive BuildCenter, icon web app mồ côi.
- Không quét dữ liệu app iOS khác; content blocker chỉ áp dụng cho WebView mở trong APLite.
- Tái dùng Keychain/Data Protection hiện có; dữ liệu nhạy cảm được redaction trước khi ghi log hoặc xuất khảo sát.

## 6. Khảo sát Beta (chỉ bản beta)
- Cử chỉ: **giữ 4 ngón tay ~0.6s**. Một lần chạm 4 ngón vẫn mở menu app như cũ. Có thêm nút “Start a survey” trong màn hình xuất khảo sát.
- Kéo chọn vùng → xem lại ảnh → ghi chú → lưu. Ảnh chụp từ snapshot desktop trước khi hiện overlay.
- Xuất một tệp JSON: `aplite.beta-survey.v1`, gồm ảnh base64, ghi chú, timestamp, phiên bản và metadata thiết bị/nhiệt/low-power. Tối đa 12 bản ghi, ảnh tự thu nhỏ. Chia sẻ qua Files / iCloud Drive.

## 7. Kiểm chứng
- Kiểm tra tĩnh tại repo: JSON/plist/YAML parse, cân bằng delimiter 24 file Swift, lint thiết kế (file mới **0 FAIL**; baseline dự án vẫn 22 FAIL), `git check-ignore` cho thư mục skill.
- Build IPA + unit test chạy trên CI macOS — CI là nguồn chân thực. **Chưa xác nhận trên thiết bị thật**; xem `SYSTEM_TEST_PLAN.md` mục 1.3.0 và `AUDIT_1.3.0_IMPLEMENTATION.md`.

APLite là dự án độc lập dựa trên iDesk gốc của itshieuk: https://github.com/itshieuk/iDesk — không phải phát hành chính thức hay được xác nhận bởi dự án gốc.
