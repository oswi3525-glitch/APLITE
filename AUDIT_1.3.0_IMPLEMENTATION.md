# APLite 1.3.0 — triển khai boot fix + các tab mới (Beta 1)

Tài liệu bổ sung cho `AUDIT_1.3.0_PHASE0.md` và `AUDIT_1.3.0_PROGRESS.md`. Không thay thế hai tài liệu đó.

## 0. Ràng buộc môi trường (đọc đầu tiên)

Container này **không có** Xcode / Swift / Simulator (`which swiftc` → rỗng); chỉ có Node 24.
Vì vậy mọi kiểm tra dưới đây là **tĩnh**: cân bằng delimiter, JSON parse, lint thiết kế SwiftUI,
soát diff. **Không có tuyên bố build/test/thiết bị.** CI (`Build APLite`) và `SYSTEM_TEST_PLAN.md`
vẫn là cổng quyết định. Theo yêu cầu phát hành, metadata đã được nâng lên **1.3.0 (beta 1)** và
kênh beta đã bật; điều đó **không** thay thế việc CI build/test/device — xem §6.

Ghi nhận tác giả gốc (iDesk / itshieuk, MIT) vẫn nguyên vẹn trong `APLite.swift`, `NOTICE.md`,
`LICENSE`, README; không thêm tuyên bố APLite là dự án gốc hay được chứng thực.

## 1. Ưu tiên 1 — lỗi treo màn hình khởi động

### 1.1 Nguyên nhân (audit tĩnh, có file:dòng)

| # | Nguyên nhân | Bằng chứng trước fix |
| --- | --- | --- |
| 1 | Mọi bước boot chạy **đồng bộ trên main queue**; watchdog 20s cũng nằm trên **cùng main queue** → một bước block main thì watchdog không bao giờ chạy được, màn hình retry vô hiệu. | `BootExperience.swift` `DispatchQueue.main.async` (step) và `DispatchQueue.main.asyncAfter` (watchdog) |
| 2 | `AudioSessionManager.start()` → `activatePlayback()` → `notifyResumed()` → closure `resumeWebAudio` → **first-touch `DesktopModel.shared` ngay trong boot step 2**. Singleton này quét guest app, đọc Keychain, đo thư mục, biên dịch content blocker… | `AppDelegate.swift:20-37`, `AudioSessionManager.swift:90,119,254`, `DesktopModel.swift:656-730`, `GuestStore.swift:91-189` |
| 3 | Cờ legacy `iDesk.clearCachesOnLaunch` (có thể sót sau khi nâng cấp) khiến `GuestStore.init()` **xoá toàn bộ `Library/Caches` đồng bộ trên main** — có thể hàng GB. | `GuestStore.swift:114-121,137` |
| 4 | Ở chế độ preview không có external scene, `desktopReady` không bao giờ được set → overlay boot trên desktop **không bao giờ tắt**. | `DesktopView.swift:47-60`, `SceneDelegates.swift:111-120`, `PreviewController.swift` |
| 5 | Không có instrumentation nào cho boot: không timestamp, không log theo phase → không thể biết bước nào chậm. | `BootExperience.swift`, `AppDelegate.swift` (trước fix: 0 log) |

Không tìm thấy: `sleep`/semaphore/`.wait()`/`main.sync` trong boot, prewarm lặp, overlay `onDrop` trong `body`,
stale `UISceneStoryboardFile`, hay xung đột kiểu UserDefaults gây crash. Scene manifest khai báo 3 lần
(`Info.plist`, `project.yml`, `configurationForConnecting`) nhưng tên/class trùng nhau → redundant, không phải nguyên nhân treo; **giữ nguyên** theo nguyên tắc Preserve.

### 1.2 Đã sửa (sau)

- **Watchdog rời khỏi main queue** (`BootExperience.swift`): chạy trên `DispatchQueue.global(qos: .utility)`,
  ghi ngay `APLog.fault` có timestamp từ luồng nền, rồi mới hop về main để hiện lại UI retry cũ.
  Nhờ vậy dù main bị block, vẫn có bằng chứng thời gian và fail state sẽ áp dụng khi main rảnh.
- **Chặn heavy init trong audio callback** (`AppDelegate.swift`): ba closure `guestAppsActive`,
  `audioInUse`, `resumeWebAudio` trả về giá trị an toàn khi `BootCoordinator.servicesReady == false`.
  Trước khi boot xong vốn không có window/tab nào để kiểm tra, nên hành vi thực tế không đổi.
- **Xoá cache ra background** (`GuestStore.swift`): phần `Library/Caches` được đưa vào cùng sweep
  `utility` vốn đã xử lý `tmp/`; flag legacy vẫn được đọc/xoá như cũ (backward compatible).
- **Preview tự đóng overlay** (`PreviewController.swift`): đăng ký `whenServicesReady` rồi gọi
  `finishDesktopPreparation()`. Không ảnh hưởng luồng external display thật.
- **Instrumentation bắt buộc** (`APLog`, mới): `Boot started`, `Boot step started/finished: … in N ms`,
  `Boot failed`, `All boot services ready`, `Desktop preparation finished`, và `fault` khi watchdog chạy.
  Đây là bằng chứng thời gian thay cho cảm giác “nhanh hơn”. Không dùng delay giả.

### 1.3 Cách đọc log trên thiết bị

Log ghi song song: Unified Logging (`os_log`, subsystem `com.hieuk.aplite`, category `SystemLog`)
và file `Library/Application Support/APLite/Logs/aplite-system.log` (xem trong Cài đặt →
Quyền riêng tư & Bảo mật → Nhật ký hệ thống). Rotate ở 512 KB, giữ tối đa 2 bản cũ; redaction dùng
lại `DiagnosticsPolicy.redact`. Không dùng `OSLogStore` hay private API.

## 2. Các hạng mục khác đã triển khai

| Mục | File mới / thay đổi | Ghi chú |
| --- | --- | --- |
| Cài đặt 5 tab | `System/SettingsTabContainer.swift`, `Controller/SettingsSheet.swift` | Adapter: tab **Hệ thống** là `SystemSettingsView` **nguyên vẹn**, nên mọi key/action cũ giữ nguyên. 4 tab còn lại bổ sung, không xoá item. Mặc định tab Hệ thống. Desktop HTML Settings không đụng vào. |
| Nhật ký hệ thống | `System/APLog.swift`, `APLogModel.swift`, `SystemLogView.swift` | Dual-write, 4 mức, timestamp/module, lọc, xoá, persist + rotation. |
| Dọn rác | `System/CleanupPolicy.swift`, `CleanupManager.swift`, `CleanupSettingsView.swift` | Chỉ quét sandbox APLite: cache, tmp prefix, log xoay, diagnostics cũ, BuildCenter zip, icon web app mồ côi. Không quét app khác. Có content blocker sẵn trong WebView (`ContentBlocker.swift`) — giữ nguyên, không mở rộng. |
| Bảo mật | `PrivacySettingsView.swift` + `APStoreIntegrity` | Tổng hợp quyền/passcode/tài khoản; hash SHA-256 để kiểm tra toàn vẹn module. Không hứa “diệt virus toàn hệ thống”. |
| APStore | `System/APStoreCatalog.swift`, `APStoreView.swift` | Phân biệt **Web Apps** (lối tắt, cài qua `WebApps.install`) và **Native Modules** (mã đã ký cùng APLite, quản lý qua `GuestStore`). Nêu rõ iOS cấm cài IPA tuỳ ý; không có gói `.aplite` trong codebase nên không bịa ra. |
| Khảo sát beta | `System/BetaSurvey.swift`, `BetaSurveyCaptureView.swift`, `SurveyExportView.swift`, `TrackpadView.swift`, `DesktopView.swift` | Xem §3. |
| Skill design | `.agents/skills/{taste-skill-swiftui,ios-app-beauty}`, `~/.agents/skills/swiftui-design-skill` | Đã đọc trước khi làm UI. `.gitignore` đã chặn **mọi** `.agents/skills/` và `.taste-skill/`; không commit/bundle skill hay script của skill. |

Nguyên tắc thiết kế đã áp dụng: native-first (`TabView`, `List`, `NavigationStack`, `ContentUnavailableView`,
`.sheet`, system haptic), dùng token có sẵn (`APLiteDesign`, `APLiteColors`, `APLiteAnimation`), SF Symbols,
góc continuous, 44pt tap target, Reduce Motion/Dynamic Type theo hệ thống, không gradient/tím/icon-card/emoji.
Kết quả lint: **14 file mới = 0 FAIL**; toàn dự án vẫn **22 FAIL / 304 WARN** như baseline (toàn lỗi cũ).

## 3. Kích hoạt Beta và cử chỉ khảo sát

- `APLite.channel` đọc `APLiteReleaseChannel` từ Info.plist. **Bản này đặt `"beta 1"`** → `APLite.isBeta == true`,
  `APLite.displayVersion == "1.3.0 (beta 1)"`. Stable để trống → ẩn hoàn toàn tính năng beta.
- Lưu ý giá trị channel chỉ là hậu tố: ghi `"beta 1"`, không ghi `"1.3.0 beta 1"` (né trùng `1.3.0 (1.3.0 beta 1)`).
- Metadata đã cập nhật: `project.yml` (`MARKETING_VERSION: 1.3.0`, channel `beta 1`), `Info.plist`,
  `CHANGELOG.md`, `README.md`, `README.vi.md`, `aplite-live.json` (`version: 8`), in-app `SystemChangelog`,
  `SYSTEM_TEST_PLAN.md §1.3.0`, `RELEASE_NOTES_1.3.0.md`. Bundle ID/khoá lưu trữ/attribution không đổi.
- **Quyết định cử chỉ:** 4 ngón **chạm** đã gắn từ trước với menu app (`TrackpadView.finish` → `toggleLauncher`).
  Để không đổi hành vi cũ, khảo sát dùng 4 ngón **giữ ~0.6s** (chỉ khi beta). Nút “Start a survey” trong
  màn hình xuất khảo sát là lối vào thay thế. Nếu bạn muốn chuyển sang 4 ngón chạm đơn, cần đổi
  `TrackpadView` và chấp nhận mất menu app — vui lòng xác nhận trước khi đổi.
- Luồng: capture snapshot desktop **trước khi** hiện overlay → kéo chọn vùng → xem lại ảnh + ô ghi chú →
  lưu. File xuất là một JSON: `schema = aplite.beta-survey.v1`, `hint`, `exportedAt`, `app`,
  `attribution`, `records[]` (ảnh base64, ghi chú, timestamp, device/thermal/low-power/version).
  Tối đa 12 bản ghi, ảnh tự thu nhỏ để export không phình. Share qua `UIActivityViewController`.

## 4. Kiểm thử

### 4.1 Đã chạy ở đây (tĩnh)
- Parse JSON: `Localizable.xcstrings` (879 khoá, EN source + VI), `Assets/registry.json`, `skills-lock.json`.
- Cân bằng `{ } ( ) [ ]` trên 24 file Swift đã đổi/mới (bỏ qua string/comment): tất cả OK.
- `lint.mjs` của taste-skill-swiftui: file mới 0 FAIL; baseline dự án không tăng.
- `git check-ignore`: `.agents/skills/*` bị ignore → không thể commit nhầm skill.

### 4.2 Bắt buộc trước khi gắn nhãn 1.3.0 (CI / thiết bị)
1. `xcodegen generate` → build Release → chạy toàn bộ unit test (có thêm `APLogPolicyTests`,
   `CleanupPolicyTests`). Kiểm tra không có lỗi actor-isolation từ closure `@MainActor` (Swift 5 mode).
2. Boot: cold launch có/không màn hình ngoài, bật/tắt lock-on-launch, background→foreground (không replay boot),
   disconnect/reconnect display. So sánh timestamp các dòng `Boot step … in N ms` trước/sau.
3. Giả lập bước boot chậm để watchdog nhả: phải log `fault`, hiện retry, và completion muộn không chạy nền.
4. Preview mode (`-APLitePreview`): overlay desktop phải tự tắt.
5. Settings: mở sheet không display và có display; desktop action `systemSettings` vẫn vào đúng tab Hệ thống;
   TV mode, passcode, shutdown confirm, keyboard/advanced/changelog/about push, mouse/setup/welcome sheet.
6. Beta: build có channel → thử 4 ngón giữ, kéo vùng, lưu, export JSON, kiểm tra stable build không thấy mục này.
7. Dọn rác: scan → xoá → kiểm tra User files/guest app còn nguyên; log ghi đúng số item/byte.
8. Chỉ sau 1–7 xanh mới đổi đồng loạt `MARKETING_VERSION`, changelog, README, live manifest.

## 5. Phạm vi còn lại / không làm (có chủ đích)

- Chưa dời từng `Section` cũ sang tab khác: `SystemSettingsView` được giữ nguyên làm tab Hệ thống theo
  nguyên tắc “không rewrite, không xoá tính năng cũ”. Việc tái phân bổ sâu từng mục cần build giữa chừng
  (một surface / một commit như `UI_SYSTEM_PLAN.md`), không nên làm mù trong container này.
- Desktop HTML Settings chưa tab hoá (rủi ro chuỗi JS/bridge cao khi không build được).
- Không có prewarm nào trong codebase để guard bằng `isLowPowerModeEnabled`/`thermalState`; thay vào đó
  đã đảm bảo các công việc nặng khi boot không còn chạy đồng bộ trên main. Metadata khảo sát có ghi thermal/low-power.
- Không triển khai mã hoá tuỳ ý cho mọi tệp; dùng lại Keychain/Data Protection hiện có của `SecurityManager`,
  `SigningStore`, `BuildCenter` và redaction cho export.

## 6. Trạng thái phát hành 1.3.0 (beta 1)

- Nhãn beta đã được gắn vào metadata (xem §3). `APLite.isBeta == true` trên bản này.
- **Chưa có bằng chứng CI/device** trong container này. Các mục 1–7 của `SYSTEM_TEST_PLAN.md §1.3.0`
  phải xanh thì mới coi beta 1 là phát hành được. Không được suy từ “đã đổi số phiên bản” sang “đã kiểm chứng”.
- Artifact dự kiến: `APLite-unsigned-1.3.0.ipa` (chưa ký; tự ký bằng ESign/Feather/Scarlet/SideStore).
- Stable build: chỉ cần để `APLiteReleaseChannel` trống; không cần xoá code khảo sát.

### 6.1 CI run đầu tiên: FAILED → đã vá

- Run `45300767219` (`Build APLite`, commit `62f0e5c`, 24/11/2026) **Build failed**, 4 dòng `error:`:
  1. `BetaSurveyCaptureView.swift:117` — `'TextEditor' cannot be constructed…`: dự án đã có `enum TextEditor`
     trong `Desktop/TextEditor.swift` nên tên bị shadow. Sửa: gọi rõ `SwiftUI.TextEditor`.
  2. `SurveyExportView.swift:69` — `invalid redeclaration of 'ShareSheet'`: đã có `enum ShareSheet` trong
     `Controller/SystemSheets.swift`. Sửa: bỏ representable tự định nghĩa, dùng lại `ShareSheet.present(url)`.
  3. `SurveyExportView.swift:57` — hệ quả của (2): `.sheet { ShareSheet(items:) }` không còn initializer. Sửa: gọi trực tiếp `ShareSheet.present` từ nút export.
  4. `SystemLogView.swift:19` — `ForEach` yêu cầu `APLogLevel: Identifiable`. Sửa: `ForEach(APLogLevel.allCases, id: \.self)`.
- Cảnh báo `AudioSessionManager.swift:308 switch must be exhaustive` là **có sẵn** (không thuộc thay đổi này).
- Cảnh báo `BetaSurveyCaptureView.swift:74 'source' unused` cũng được dọn trong lần vá này.
- Bản vá được commit riêng (`fix(build): …`) để CI có thể đối chiếu trước/sau. Chưa coi beta 1 là xanh cho đến khi run mới **success**.
