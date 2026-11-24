# APLite 1.3.0 (beta 1) — Audit toàn repo & kế hoạch hoàn thiện

Trạng thái: **đang tổng hợp** (4 luồng audit song song: bảo mật, UI/design, correctness/build/docs).
Tài liệu này là nơi duy nhất chứa kết quả audit full-repo; không thay thế các audit theo phase trước đó.

## 0. Baseline tại thời điểm bắt đầu (24/11/2026)

| Hạng mục | Giá trị |
| --- | --- |
| Commit | `b4ff898` (sau `62f0e5c` release 1.3.0 beta 1) |
| Nhánh / remote | `fix/1.2.8-patch-release`, khớp `origin`, không divergence |
| Tag / Release | `v1.3.0-beta.1` (prerelease), CI build + unit test **success** (run `45302823719`) |
| Version metadata | `MARKETING_VERSION=1.3.0`, channel `beta 1` → `APLite.displayVersion = 1.3.0 (beta 1)` |
| Design lint baseline | 126 file Swift, **22 FAIL / 304 WARN** (toàn lỗi/cảnh báo có trước đợt này) |
| Kiểm tra tại chỗ | Không có Xcode/Swift/Simulator; CI là nguồn build/test chân thực |
| Working tree | Sạch; chỉ `skills-lock.json` cố ý để untracked (dữ liệu môi trường, không commit) |

## 1. Phương pháp

Giữ nguyên nguyên tắc đã dùng: **Preserve → Abstract → Replace → Verify**.

- **Preserve:** không stash/reset/rebase, không rewrite toàn dự án, không xoá tính năng cũ, không thay code chạy được bằng mockup. Attribution iDesk/itshieuk + LICENSE/NOTICE giữ nguyên.
- **Abstract:** tách chính sách thuần (policy) thành file Foundation-only để unit-test; dùng adapter khi cần thay thế (ví dụ đã dùng `ShareSheet.present` có sẵn thay vì định nghĩa lại).
- **Replace:** chỉ thay từng điểm có bằng chứng (file:dòng) và có log trước/sau.
- **Verify:** local = JSON/plist/YAML parse + delimiter + design lint + unit test thuần; xa hơn = CI build + test + thiết bị.

Giới hạn phân bổ công việc:

1. Phase A — audit (đang chạy).
2. Phase B — hoàn thiện giao diện: **một surface / một commit**, ưu tiên thay literal bằng token; không đổi cấu trúc khi chưa có bằng chứng trên máy thật. Mỗi commit push lên CI.
3. Phase C — sửa lỗi & lỗ hổng bảo mật: theo mức độ, có unit test cho logic thuần, có log trước/sau vào Nhật ký hệ thống.

## 2. Phát hiện audit

_(sẽ điền từ 4 báo cáo: bảo mật / UI / correctness / build-config)_

## 3. Kế hoạch UI (một surface / commit)

_(sẽ điền)_

## 4. Kế hoạch sửa lỗi & bảo mật

### 4.1 Đã vá ngay trong Phase C (đợi báo cáo audit đầy đủ để bổ sung)

| Mức | Vấn đề | Trước | Sau |
| --- | --- | --- | --- |
| Medium | Cookie đăng nhập lưu JSON plaintext, **không có Data Protection** — file vẫn đọc được khi máy khoá (sandbox không tự mã hoá). | `CookieVault.swift:100,163` ghi `.atomic` | ghi `[.atomic, .completeFileProtectionAfterFirstOpen]` — vẫn đọc được lúc boot, khoá lại khi máy khoá |
| Low | Log hệ thống và file xuất khảo sát (có ảnh màn hình) cũng là dữ liệu nhạy cảm. | `APLog.swift:115`, `BetaSurvey.swift:77` ghi `.atomic` | thêm `.completeFileProtectionAfterFirstOpen` |
| Low | Crash report/heartbeat dùng chế độ `0644` (rộng hơn cần). | `CrashReporter.m:197,432` `0644` | `0600` |

Không có thay đổi API, format file hay khoá lưu trữ; chỉ thêm thuộc tính bảo vệ của iOS. Chưa thay thế việc
mã hoá cookie bằng Keychain — đó là việc lớn hơn, cần đánh giá riêng (xem phát hiện audit bảo mật khi có).

### 4.2 Chưa làm / chờ kết quả audit

_(sẽ điền từ báo cáo bảo mật, correctness, build/docs)_

## 5. Nhật ký thực thi

| Thời điểm | Hành động | Kết quả |
| --- | --- | --- |
| 24/11/2026 | Khởi tạo baseline audit | lint 22 FAIL / 304 WARN, CI beta 1 xanh |
| 24/11/2026 | Phase B+C: 42 file, +513/−63 | 3 lần CI fail do API Data Protection/protection type sai + regex redaction ăn `&next`; đã vá |
| 24/11/2026 | CI cuối `45307515029` | **success** — build + unit test + upload IPA, commit `b821d01` |

## 6. Kết quả sau audit (đã push)

- Design lint: **16 FAIL / 303 WARN** (giảm 6 FAIL: 1 token swap + 5 `taste:allow` có lý do). 16 FAIL còn lại là gradient/wallpaper/product identity — **cần capture sáng/tối + focus state trên thiết bị**, không đổi mù.
- Bảo mật đã vá: redact crash report trước khi đưa lên GitHub issue public; mở rộng redaction (JSON, Bearer, api_key, pin, session) + test; Data Protection cho cookie/log/khảo sát; Keychain signing dùng `WhenUnlockedThisDeviceOnly` + migration; chặn `CFBundleExecutable` path traversal; Unzip prefix/overflow; main-frame guard Files bridge; BuildCenter chỉ gửi Bearer tới host GitHub + strip auth khi redirect khác host + escape segment; nhãn APStore trung thực; redact ghi chú khảo sát.
- Lỗi đã vá: khảo sát chuyển ra **phone surface** (external scene không nhận drag); cleanup scan & log read ra nền; **Auto-lock after hoạt động lại**; `APLiteSettings.bool` không còn ép `NSNumber(1)` thành `true`; huỷ hold 4 ngón khi tay dịch chuyển; không xoá icon web app khi registry decode hỏng; không xoá cache WebKit.
- Phát hành: channel mặc định rỗng (build HEAD là stable), beta chỉ bật qua release input; `MARKETING_VERSION` nhận bản số học (`1.3.0`) thay vì `1.3.0-beta.1`; notes lấy từ `RELEASE_NOTES_1.3.0.md`; `VersionCompare` + test; `skills-lock.json` bị ignore; bổ sung 16 khoá VI + plural VI.

## 7. Còn lại (cần quyết định / thiết bị)

1. **Tag `v1.3.0` cũ trỏ tới `46a92b1`** (mã 1.2.9,MARKETING_VERSION 1.2.9) nhưng release mang tên 1.3.0. Việc dời/xoá tag là **history rewrite** → cần bạn uỷ quyền rõ ràng; tôi không tự làm.
2. Beta artifact hiện tại (`v1.3.0-beta.1`) vẫn hiển thị `1.3.0-beta.1 (beta 1)` do workflow cũ. Muốn đúng `1.3.0 (beta 1)` cần **publish lại release** sau khi workflow mới đã sửa — cần bạn xác nhận (xoá tag/release cũ rồi tạo lại, hoặc tạo `v1.3.0-beta.2`).
3. **A7 (race cache wipe vs WebKit restore)** chưa sửa: nên đưa legacy wipe thành boot step đầu tiên trước `CookieVault.restore()`, thay vì trong `GuestStore.init()`.
4. **PBKDF2 cho passcode** chưa làm (vẫn SHA-256 + salt); cần migration có phiên bản — để lại do rủi ro cao khi không có thiết bị thử.
5. Persistence silent-decode (B3), `main.sync` latent (B4), queue dữ liệu AccountCookies (B5), `systemUsage()` tính trong `body` (B6), cleanup reporting success khi xoá hỏng (A4) — đã giảm phạm vi nhưng chưa xử lý hết.
6. UI: 16 gradient FAIL + hand-glass/shadow/type-scale WARN cần capture thiết bị (sáng/tối, AX5, focus) — không đổi mù khi chưa có bằng chứng hình ảnh.
7. Tài liệu stale: `README.vi.md` vẫn hướng dẫn tải IPA từ repo iDesk gốc (D5), `ARCHITECTURE.md`/`UI_SYSTEM_PLAN.md`/`INDEPENDENCE.md` cần cập nhật theo 1.3.0.

---

## 8. Đợt 2 — yêu cầu mới (24/11/2026)

Giữ nguyên các phần 1–7 ở trên. Đợt này audit + sửa theo báo cáo lỗi của người dùng:

1. Dock: đưa vào giữa màn hình desktop.
2. Trình duyệt: lỗi mở Zalo, lỗi skip quảng cáo YouTube, lỗi asset/icon.
3. Chứng chỉ: `The certificate file is damaged or truncated…` và lỗi mật khẩu `.p12`.
4. Tính năng mới: thêm app IPA vào màn hình chính desktop; mở bằng cửa sổ.
5. Đẩy lên `main`; dọn cache trước khi làm.

Kết quả audit chuyên sâu và thứ tự sửa sẽ được ghi tiếp tại đây.

