# APLite 1.2.7 — PHASE 0 repository audit (before any code change)

Date: 2026-11-23 · Branch: `fix/audio-and-hardening` · HEAD: `3114f5a` (= tag `v1.2.6`) · tree clean.
Method: full static review of 98 Swift sources (~26.8k lines with ObjC), project/CI/scripts/docs, plus
7 parallel deep audits and WebKit/Gmail behavior research. **No files were modified in this phase.**
No Xcode exists in this Linux container: build/test evidence can only come from GitHub Actions.

## 1. Current architecture (verified)

- **Generated Xcode project**: `project.yml` → `APLite.xcodeproj` via XcodeGen. Two targets: `APLite`
  (all of `APLite/`, automatic signing, unsigned build via `CODE_SIGNING_ALLOWED=NO`) and the standalone
  `APLiteTests` (only `Tests/` + 11 explicitly listed pure files; no host app).
- **Identity**: display name `APLite`, bundle id `com.hieuk.idesk` (**intentionally frozen** for data
  compatibility), iOS 17+, `MARKETING_VERSION = 1.2.6`, `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
  overridden by CI run number. No entitlements file, no registered URL scheme: `idesk://` is an
  **internal WKWebView page scheme**.
- **Two scenes**: `PhoneSceneDelegate` hosts the iPhone trackpad/keyboard (`ControllerView`);
  `ExternalSceneDelegate` hosts `DesktopView` on HDMI/AirPlay. The external scene **receives no
  touches** — every interaction is synthetic hit-testing inside the `DesktopModel` singleton
  (self-drawn cursor via `CursorModel`, `click()`/`mouseDown()`/drag state machine).
- **Window model**: `DesktopModel.windows: [DeskWindow]`; a `DeskWindow` is `.browser`, `.system(page)`
  or `.guest`. Browser tabs are `WKWebView`s; web apps are browser windows with `isWebApp = true`
  (no address bar/tabs unless a sign-in popup opens one). `WebViewHost` only returns the existing
  WKWebView — SwiftUI never creates WebKit views.
- **Browser**: ordinary `WKWebView` with a fresh `WKWebViewConfiguration` per tab. Nine user scripts,
  six message handlers, `preferredContentMode = .desktop`, shared `WKWebsiteDataStore.default()`,
  no custom UA, no `WKProcessPool`, no `applicationNameForUserAgent`.
- **Settings**: native `SystemSettingsView` on iPhone (`APLiteSettings` → `APLite.*` UserDefaults,
  `@AppStorage` bindings) and the desktop HTML page `idesk://settings` (`DesktopPages.settingsState()`
  → JS `render(state)` → `send(action,value)` → `handle()` → `refresh()`). Any new setting must be
  added to both surfaces, plus `Localizable.xcstrings`.
- **Guest Engine**: `Guest/*.m`, Mach-O patching, signing, in-process IPA runtime. Byte-for-byte
  compatibility requirement; no changes in 1.2.7 except two *user-visible strings* in `GuestShims.m`
  and the exported IPA filename in `GuestStore.swift` (no data/identifier impact).
- **CI**: `build.yml` (push to `aplite-dev`/`fix/**`, Xcode 16/macOS 15, build IPA + `APLiteTests`,
  upload `APLite-unsigned.ipa`); `release.yml` (tag `v*` or dispatch; injects `VERSION` from the tag,
  builds `APLite-unsigned-<version>.ipa`, publishes release).

## 2. Findings & root causes by phase

### PHASE 1 — Browser / Gmail (highest priority)
1. **Gmail banner root cause: anonymous desktop UA.** `DeskWindow.swift:285` requests `.desktop` but
   **no UA API is set anywhere** in the repo. WebKit's desktop UA without `applicationNameForUserAgent`
   is `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)`
   — it lacks the `Version/<n> … Safari/<build>` tokens Google's support gate expects. This is the
   same failure mode as cmux #9052 (2026). Fix truthfully with `applicationNameForUserAgent` carrying
   the **real** Safari version derived from the OS, not by faking Chrome or hiding the banner.
2. Popups (`createWebViewWith`, `DeskWindow.swift:558`) inherit WebKit's configuration; UA/content
   mode are not re-asserted → OAuth popups may get the wrong UA.
3. No `webViewWebContentProcessDidTerminate` implementation → blank tab after WebContent kill.
4. No shared `WKProcessPool` → more WebContent processes, higher memory/termination risk.
5. `deinit` detaches handlers unconditionally, unlike `detach(_:)`'s sharing guard.
6. `discardBackgroundTabs()` can destroy live OAuth/Google sign-in tab state.
7. `DesktopSite.script` overrides touch/screen/matchMedia in **every frame**; `WebFullscreen`/`WebVolume`
   patch prototypes per frame. Not the Gmail banner, but framework/iframe risk.
8. **BLOCKED by iOS/WebKit**: Service Workers (no web-browser entitlement), WebAuthn/passkeys in
   embedded WKWebView, a real Chromium engine, hiding Google's banner, a static fake UA, direct Safari
   cookie access. None will be attempted.

### PHASE 2 — Color system
1. Accent is consistent blue `#38BDF8` (asset + CSS). There is **no pure red** anywhere; all reds are
   dynamic system colors or pastel RGB literals → under forced dark mode `.systemRed` resolves to
   coral/pink `#FF453A`, and alpha reds over white glass (`ScreenRecorder:149`, `TaskManager:166`,
   `LaptopMode:194`, `MediaModes:107`) composite to pink.
2. CSS "danger" literals are literally pink: `#ff8a80` (`DesktopPages:705`, `FileStore:254`),
   `#ff6961` (`.bad`, `DesktopPages:726`); four different "accent blue" literals across CSS.
3. `Color(hue:saturation:brightness:)` (`DesktopView:373-374`) uses the `.device` color space →
   P3 devices shift colors. `cssColor`/`cssColors` don't clamp extended-range RGB.
4. `LiveUpdate.swift:40-43,59` lets a remote manifest replace `.accentColor` globally — a future
   pinkish value would repaint the whole UI. Current manifest is `accent: null`.
5. Night-filter `.blendMode(.multiply)` and animation interpolation were **ruled out** as causes.

### PHASE 3 — App management / Trash
1. Two distinct app classes exist: **WebApps** (`WebApps.shared`, `iDesk.webApps` — APLite-managed web
   shortcuts) and **guest IPA apps** (`GuestStore`, `iDesk.pendingRemoval` — removal applied on next
   reinstall; bundled apps cannot be deleted in-process). Native iOS/App Store apps **cannot** be
   uninstalled — no API/entitlement; must be documented, never claimed.
2. Existing drag state machine (`DesktopModel.drag = .icon(Shortcut, from:)`, `iconDrag`,
   `iconDropSlot`, `desktopIcon(at:)`, `DraggedIconView`) is for desktop icons/app-menu items and is
   reusable for WebApp/Guest icons; Trash already has `Trash.move/restore/deleteForever` plus
   `iDesk.trashOrigins` for file restore.
3. Need: explicit drop detection into the icon zone, confirmation, removal from Launcher/Desktop/Dock,
   animation bounded to APLite-owned data, and a clear capability boundary for guest apps.

### PHASE 4 — WebApp zoom
1. Two divergent level tables: `PageZoom.levels = [0.9,1,1.15,1.3,1.5]` (Settings UI) vs a hardcoded
   `[0.5,0.67,0.75,0.8,0.9,1,1.1,1.25,1.5,1.75,2,2.5,3]` in `DesktopModel.zoom(_:)`; TV mode forces
   `1.3`, which is in neither table consistently.
2. Per-tab zoom is in-memory `ObjectIdentifier(web)` only — lost on close/restart. No per-WebApp zoom.
3. CSS `zoom` injection needs reapplication on every navigation (`didCommit`, `didFinish`,
   DOMContentLoaded) and once caused a listener leak. **Official `WKWebView.pageZoom` (iOS 14+) is
   documented as equivalent to CSS zoom**; it is available under our iOS 17 target and is the safer
   single mechanism. The existing comment claiming pageZoom magnifies past edges actually describes
   `magnification`, not `pageZoom` — correct it. Never run both mechanisms at once.
4. Stable app key: `initialURL.absoluteString` matched via `Browsing.same` against the `WebApps` entry
   — never `currentURL`, `tab.url` or `title` (redirects change them).
5. `WebInput.scaleHead` self-corrects through `window.innerWidth/vw`; keep it untouched and verify
   synthetic clicks/hover under native pageZoom on device.

### PHASE 5 — Branding
376 case-sensitive `iDesk` occurrences in 60 files: the overwhelming majority are required
compat identifiers (bundle id, `iDesk.*` keys, `idesk://` scheme, `iDeskGuest_` prefixes, launch args,
`__idesk*` JS bridges), required upstream attribution (LICENSE/NOTICE/About/APLite.swift), or frozen
historical docs (including `README.vi.md`). Only five user-facing fixes are safe:
`.github/ISSUE_TEMPLATE/bug_report.yml:2,15,23`; `GuestShims.m:588,931,943` (user-visible error text);
`GuestStore.swift:407` (export filename); `.gitignore:17` (stale `iDesk.xcodeproj/`);
`APLite.swift:5` (wrong upstream URL in a comment). Keep every attribution line verbatim.

### PHASE 6 — Performance
1. `objectWillChange.send()` on **every pointer event** during widget/sticky drag
   (`DesktopModel:1957-1963`) rebuilds the whole desktop (blend modes, materials, windows) at 60–120 Hz.
2. `MemoryManager.sample()` republishes 7 `@Published` values every 10 s with no equality guard,
   invalidating tray/Task Manager views unnecessarily.
3. `GuestWindowHost` 1 s watchdog runs for a guest window's whole lifetime; observers never removed.
4. `UserDefaults.didChange` triggers both an observer send and a separate merged publisher → duplicate
   `DesktopPages.refresh()` scheduling.
5. Many raw `withAnimation`/`.animation` calls bypass `APLiteAnimation.reduced` (Reduce Motion/thermal).
6. No true retain cycles, no uncapped caches found; KVO and message-handler teardown are correct.
   Guest Engine, main-thread UIKit capture and WebKit KVO teardown are **not safe to rewrite**.

### PHASE 7/8 — Tests, docs, build
- `MARKETING_VERSION` 1.2.6; live manifest numeric version is 5 → must become 6 or the new notice is
  ignored (`LiveUpdate.swift:52`). Update README, in-app changelog, CHANGELOG, new release notes.
- `release.yml` has no test step and no `xcode-select`, yet its generated notes claim tests passed.
- `UpdateChecker.swift:94` fallback URL `APLite-<version>.ipa` ≠ release asset `APLite-unsigned-<version>.ipa`.
- No lint script exists; static checks so far were manual. New pure helpers (UA builder, zoom math,
  color parser, trash policy) must be Foundation-only and registered in `project.yml`'s test sources.

## 3. Files planned to change (no architectural rewrites, Guest Engine preserved)

| Phase | Files |
|---|---|
| 1 | `APLite/Desktop/DeskWindow.swift`; new `APLite/Desktop/BrowserUserAgent.swift` (+ test) |
| 2 | new `APLite/System/APLiteColors.swift`; `DesktopView.swift`, `ScreenRecorder.swift`, `TaskManager.swift`, `LaptopMode.swift`, `MediaModes.swift`, `ThermalMonitor.swift`, `DesktopPages.swift`, `FileStore.swift`, `LiveUpdate.swift` |
| 3 | `DesktopModel.swift`, `DesktopView.swift`, `WebFeatures.swift`, `FilesExtras.swift`/new pure `TrashPolicy`, Settings surfaces |
| 4 | `ContentBlocker.swift`, `DeskWindow.swift`, `DesktopModel.swift`, `DesktopPages.swift`, new pure `PageZoomMath` |
| 5 | 5 files listed above (branding only) |
| 6 | `DesktopModel.swift`, `MemoryManager.swift`, `DesktopView.swift`, remaining raw animations |
| 7/8 | `project.yml`, `CHANGELOG.md`, `README.md`, `aplite-live.json`, `SystemChangelog.swift`, `SYSTEM_TEST_PLAN.md`, `RELEASE_NOTES_1.2.7.md`, release workflow, new tests |

## 4. Compatibility risks / red lines
Never change: bundle id `com.hieuk.idesk`; `iDesk.*` UserDefaults / `iDesk.signing` Keychain keys;
`idesk://` and `iDeskGuest_*` identifiers; launch args; LICENSE/NOTICE/attribution; unsigned build
path; Guest Engine behavior. Never fake an engine version, hide Gmail's message, disable security,
remove working features/effects, or claim uninstall of native iOS apps. Verify all changes with CI
build + tests before tagging `v1.2.7`.
