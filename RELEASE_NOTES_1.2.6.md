# APLite 1.2.6 — Bản phát triển (unsigned)

**Ngày:** 23/11/2026 · **Artifact:** `APLite-unsigned-1.2.6.ipa` (chưa ký — phải ký bằng ESign / Feather / Scarlet / SideStore trước khi cài).

APLite 1.2.6 tập trung vào 4 việc: **lưu tài khoản đúng cách**, **bàn phím ảo trên màn hình ngoài**, **sửa tab cửa sổ** và **làm giao diện Facebook web gọn hơn**. Tất cả các tính năng cũ (Guest Engine, audio, bảo mật, Files, widget…) đều giữ nguyên.

## 1. Lưu tài khoản khi đăng nhập trong app trên màn hình ngoài

Vấn đề cũ: mọi cửa sổ web (Facebook, Zalo, Telegram, Gmail…) dùng chung `WKWebsiteDataStore.default()`, nhưng APLite chỉ lưu cookie **Google** và chỉ khi **màn hình iPhone** vào background. Đăng nhập trên màn hình HDMI/AirPlay — thường là lúc iPhone nằm úp xuống — nên không bao giờ được ghi vào vault local.

Đã sửa:
- `AccountCookies` quan sát trực tiếp `WKHTTPCookieStore` qua `WKHTTPCookieStoreObserver`, gom một đợt đăng nhập rồi lưu tự động.
- Phạm vi: các domain web app có sẵn + web app bạn tự cài + Google + cookie có tên auth (`session`, `token`, `sid`, `auth`…), giới hạn 600 cookie / 8 KB mỗi giá trị để vault luôn nhỏ.
- Flush ngay khi: iPhone vào background, **ngắt màn hình ngoài**, shutdown APLite, và qua nút "Save all accounts" trong Settings.
- `CookieVault`: ghi tuần tự bằng `NSLock`, ghi atomic, giữ lại `HttpOnly` / `SameSite`, đọc được file vault cũ, và trả đúng số cookie đã lưu (trước đây trả 0 khi refresh token → báo "chưa đăng nhập" dù đã lưu).
- Thêm nút "Save signed-in accounts" trong System settings trên iPhone; sửa thông báo sai trong desktop Settings ("Cookies from Safari" → "Accounts & cookies").

## 2. Bàn phím ảo cho desktop (mới)

- **Bật ở đâu:** iPhone → System settings → Input → *On-screen keyboard*, hoặc desktop → Settings → Typing → *On-screen keyboard*. Trang cài đặt đầy đủ: *Keyboard settings & all keys* (danh sách mọi phím, kích thước 70–130%, rung phản hồi, tùy chọn luôn hiện).
- **Chỉ hiện khi cần:** bridge focus mới (`WebInputFocusBridge`) chèn vào mọi WKWebView + kiểm tra `document.activeElement` sau mỗi cú click. Phủ luôn thanh địa chỉ, thanh find, sticky note, Files, editor và app guest.
- **Đầy đủ phím:** QWERTY, số, ký hiệu (layer `123`), Shift (1 lần), Caps Lock, Backspace, Enter, Tab, Esc, mũi tên, Home/End, Page Up/Down, Delete, Ctrl/Alt/⌘, Space, Select all / Copy / Paste.
- **Ẩn:** phím `×` trên bàn phím (trượt xuống), hoặc Esc. Click vào ô khác là hiện lại. Mặc định `Keep visible` tắt.
- Vì màn hình ngoài không nhận touch, phím được hit-test bằng CGRect trong `DesktopModel.click()`, rồi đi qua cùng đường `typeText / backspace / pressEnter / sendKey` với bàn phím cứng — nên gõ được cả web lẫn app guest.

## 3. Sửa tab cửa sổ

- Thanh find không còn dính sang tab khác khi chuyển/đóng tab.
- `⌘⇧T` mở lại tab đúng vị trí cũ (kể cả sau "Close other tabs", vốn trước đây không ghi vào undo).
- Đóng tab nền không làm mất địa chỉ đang gõ; dọn entry tab đã discard bị bỏ lại.
- Web app giữ **icon và tên thương hiệu** trên dock/switcher (trước đây là globe + `<title>` của trang).
- Thanh tab có favicon, và chữ viết tắt khi tab quá hẹp; sửa lỗi `newTabRect(count: 0)`.
- Lịch sử: tiêu đề cập nhật đúng entry dù callback `<title>` đến muộn; A→B→A trong 30 phút không tạo bản trùng.

## 4. Facebook web đẹp hơn + đồng nhất UI/UX

- `FacebookEnhancements`: CSS/JS **chỉ chạy trên `facebook.com`** — bo góc feed, header sticky dạng glass, ẩn thanh bên/chat trên cửa sổ hẹp, thanh cuộn gọn, đánh dấu bài tài trợ. Tự cài lại stylesheet nếu React của Facebook xóa nó; áp dụng lại sau mỗi lần tải trang. Có công tắc trong Browser settings, mặc định bật.
- Panel/bàn phím mới dùng chung `.floatingPanel`, `APLiteAnimation` và style keycap có sẵn; mọi chuỗi mới đều có bản dịch tiếng Việt.

## 5. Kiểm tra & giới hạn

- Đã parse cú pháp bằng tree-sitter Swift: **98 file app + 10 file test**, không có lỗi cú pháp mới (2 lỗi parser cũ nằm ở code không sửa: `#if DEBUG` và `weak` trong `ImportWeakener.swift`).
- JSON string catalog / manifest và YAML project hợp lệ; JS nhúng trong các web script qua `node --check`.
- Thêm `Tests/KeyboardLayoutTests.swift` (4 test: độ rộng hàng, vị trí panel, hit-test từng phím, layer shift/symbol).
- Build IPA và chạy unit test được thực hiện trên **macOS GitHub Actions**, không phải máy Linux này. **Chưa xác nhận trên thiết bị thật** — xem `SYSTEM_TEST_PLAN.md` mục "Accounts / On-screen keyboard / Tabs & Facebook (1.2.6)".

## 6. Ghi công

APLite là dự án độc lập dựa trên iDesk gốc của itshieuk: https://github.com/itshieuk/iDesk — không phải phát hành chính thức hay được xác nhận bởi dự án gốc.
