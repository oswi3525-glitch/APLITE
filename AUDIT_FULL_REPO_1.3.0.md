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
