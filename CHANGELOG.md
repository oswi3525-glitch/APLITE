# Changelog

All notable changes to APLite are documented here. APLite is based on iDesk v0.6.3
(upstream commit `2179dbd`); the original upstream history is not rewritten.

## 1.2.4 (unsigned development release)

- **Heat / battery**: the audio session is no longer held active forever. A new activity tracker
  (Quick Look, read-aloud, guest windows, and a JS play/pause bridge for web media) lets
  `AudioSessionManager` release the session after ~20 s of silence and on backgrounding.
- Idle WebKit/URL caches are trimmed every 5 minutes (`CacheManager`) instead of growing for the
  whole session; Quick Look's decoded image is dropped with them.
- When iOS reports thermal state `fair` or hotter, APLite automatically switches to instant
  animations (no springs/blurs/ripples) to stop feeding the heat loop.
- Built-in **web app presets**: Chrome, Zalo, Facebook, Telegram (one tap in Settings → Applications).
  Native versions still require a decrypted IPA; these are web shortcuts, clearly labelled as such.
- Meadow wallpaper and dock raise from 1.2.3 remain.

## 1.2.3 (unsigned development release)

- Dock icons raised (pill height 52 → 58 pt, top edge -6 pt).
- Google account cookies saved into APLite's local vault (also on backgrounding).
- Performance: tray redraw 5 s → 15 s, memory sampling 5 s → 10 s; no per-frame idle work added.
- App Creator: Python and Node.js templates, `project.json` build descriptor, read-only project preview.
- New bundled "Đồng cỏ" meadow wallpaper drawn by `scripts/generate_meadow.py` plus a matching gradient.
- Native System settings gained a resolution picker and a "What's new" changelog screen.
- More audio recovery hardening (interruption + route changes) and iDesk separation notes in INDEPENDENCE.md.

## 1.2.2 (unsigned development release)

- Desktop Settings → About now has **Open system settings on iPhone**, which opens the native
  System settings sheet (Security / Power / Performance / Certificates / Build Center / App Creator)
  even while an external display is connected. CI run `45016913619` passed.

## 1.2.1 (unsigned development release)

CI: `Build APLite` run `45015076389` — build + all unit test groups passed.

### Audio (tiếp tục sửa lỗi mất tiếng)

- Interruption `ended` now **always** reactivates the session a moment later, not only when
  `AVAudioSession.InterruptionOption.shouldResume` is present. Many interruptions (other app audio,
  route takeovers, Siri) end without that flag — this was the remaining cause of "silent after a
  call".
- Route changes re-assert `setActive(true)` on every change, even if our cached state says active
  (a guest app can deactivate the session behind our back).
- `VoiceTyping` now checks whether the recording session switch succeeded and fully rolls back the
  tap/request/session if `AVAudioEngine.start()` fails. Previously that path left the process in
  `.playAndRecord` and ducked every other sound.
- Web Audio: added `__ideskVolumeResume` to the injected script; after recovery APLite nudges every
  open tab so a suspended `AudioContext` starts again.
- Mute state no longer goes stale when the hardware volume buttons change the volume.

### App Creator (công cụ tạo app)

- Build Center → "Create a new app project": three real templates (Hello World, Web view, Notes),
  editable display name and Bundle ID, generates Swift sources + `project.yml`, zips them into
  APLite's managed file area, can share the ZIP or feed it straight into Build Center analysis and a
  real macOS worker. No fake compilation.

### Verification

- Build + unit tests passed on macOS CI (see run above). On-device audio checklist still pending.

## 1.2.0 (unsigned development release)

Built by GitHub Actions `Build APLite` run `45003598269` on branch `fix/audio-and-hardening`:
unsigned IPA produced and all `APLiteTests` groups passed. The sections below describe this build.
**On-device verification is still pending** — see `SYSTEM_TEST_PLAN.md` and
`AUDIO_DIAGNOSTICS.md`; no hardware behaviour is claimed as tested.

## Unreleased — system expansion & independent modules (branch `fix/audio-and-hardening`)

### Architecture

- Added `iDesk/System/` with APLite-owned modules and a one-way internal API: `APLiteSettings`,
  `SecurityManager`, `PowerManager`, `MemoryManager`, `CertificateManager`, `APLiteFileManager`,
  `WindowCoordinator`, `BuildCenter`. APLiteSettings groups are Personalization, Security, Power,
  Performance, Applications, Storage, Display, Input, Certificates and System.
- `ARCHITECTURE.md` records the audit and the separation plan. Nothing was deleted and the Guest
  Engine stays compatible.

### Security / Power

- Lock on launch, lock on sleep, authenticate on wake and configurable auto-lock.
- APLite's own passcode is stored only as a salted SHA-256 hash + salt in the Keychain, with
  exponential backoff (30 s → 2 min → 10 min → 1 h) after failed attempts. Device biometrics remain
  available; the system passcode no longer bypasses APLite's own passcode.
- Software Power Manager: Sleep, Wake and Shutdown close APLite windows, suspend guest apps,
  cancel Quick Look media, release caches and save/restore session state. **No hardware power
  control is claimed** — iOS does not allow it, and loaded code cannot be unloaded.

### Memory / Certificates / Files / Windows

- 1 GB management target, live/peak RAM display in Task Manager, warnings, bounded samples, cache
  release under pressure and a leak *hint* heuristic (never presented as proof).
- P12/PFX import now distinguishes damaged files, wrong passwords, missing private keys, missing
  certificates and missing Team IDs. Reads from Files report specific errors; no secret is logged.
- Files shows recursive folder sizes and metadata; APLite has its own managed file area with real
  diagnostics reports. Sorting is deterministic and unit tested.
- Window coordinator adds grid tiling, snapshot/restore and a reduced-motion-aware animation entry.
  Fixed the Alt+Tab/recent-apps crash from the previous release.

### Settings / Build Center / UI

- Native grouped "System settings" on the iPhone with real controls for all ten groups.
- Build Center analyses imported project files locally (sources, package/project files, Bundle ID,
  dependencies) and talks to a **real** GitHub Actions macOS worker via the API with a Keychain
  token. It only shows statuses returned by the runner and downloads artifacts from successful runs;
  no local Xcode build is simulated.
- Circular press ripple is off by default; a shared Liquid Glass button style is used by new screens.

### Verification

- **Pending**: CI build + `APLiteTests`, then the on-device checklist in `SYSTEM_TEST_PLAN.md` and
  `AUDIO_DIAGNOSTICS.md`. No feature above is claimed tested on hardware yet.

## Unreleased — audio repair and hardening (branch `fix/audio-and-hardening`)

### Fixed — audio (highest priority)

- One `AudioSessionManager` now owns the process-wide `AVAudioSession`: an active `.playback`
  baseline from launch, `.playAndRecord` only while voice typing listens, and **playback restored
  afterwards**. The old code deactivated the whole session when voice typing stopped, which silenced
  web videos, Quick Look media and guest apps until the app was restarted.
- Read Aloud now activates the shared session instead of only setting a category that was never
  activated; Quick Look media activates playback before creating its `AVPlayer`.
- Added interruption handling (call / Siri / other apps) and route-change handling (AirPods,
  Bluetooth, HDMI, AirPlay, headphones unplugged): the correct session mode is reactivated.
- Added foreground/background handling and restoration after the last guest app closes, so a guest
  app that changes the category cannot leave the desktop silent. Quick Look media resumes when the
  session comes back.
- Removed the direct `setActive(true)` from `MediaControl.start()`; it now only observes volume and
  media keys. No dummy/placeholder audio player was added — the real audio path was repaired.

### Added — audio diagnostics

- Bounded event log, snapshot of category/mode/options/route/devices, `os_log` events under
  `com.hieuk.aplite` / `Audio`, and a report available from Desktop Settings → Sound and from
  `-iDeskScript "audio"` (`audio:copy` copies it). See `AUDIO_DIAGNOSTICS.md`.
- `APLiteTests` unit target covering the diagnostics model; CI runs it on an iOS Simulator.

### Changed — Control Center / stability / performance

- Control Center (quick panel) has a fifth tile: mute, driven by the existing system volume HUD.
- Fixed Alt+Tab / Recent Apps crashes when all windows are closed while the switcher is open
  (empty-list modulo and unchecked index).
- Fixed a leaked 20 Hz key-repeat timer: it is now invalidated when the phone window is deallocated
  and no longer fires for a released window.
- File Manager: a failed "paste" no longer clears the cut items (they stay on the clipboard).
- Attributions and the Guest Engine are unchanged.

### Verification

- **Pending**: build + `APLiteTests` on the macOS CI runner for this branch, and the on-device audio
  checklist in `AUDIO_DIAGNOSTICS.md`. Nothing in this section is claimed as tested yet.

## 1.1.0 (stable)

### Added

- Task Manager panel: running windows, memory pressure, per-window close, minimize-all / close-all.
- Window close animation flies the window back to its dock icon.
- Live configuration manifest (`aplite-live.json`): data-only refresh of wallpapers and a notice,
  no IPA download and no re-signing. Native code updates still require a signed IPA.
- Performance mode: cheaper frames for AirPlay / Wi-Fi display, lighter shadows, no magnification.
- Thermal monitor (public iOS thermal-pressure API) in tray and quick panel.
- All raster assets redrawn at 4x supersampling: app icon, launch mark, lock mark, Browser/Files/
  Settings/Trash icons. Lock screen uses a dedicated LockMark and a single blur pass.

### Changed / removed

- The experimental camera window from beta was removed after review (permission, session lifecycle
  and extra UI were judged not worth the complexity for this release). Its code, asset and strings
  were reverted and verified absent in three passes (source, docs, asset catalog).
- Deeper optimisation: cached shortcut list, cached task layout, cached display modes and cookie
  domains, no per-frame magnification animation.
- Dock refined with more rounded glass, subtle highlight and softer running indicators.
- Spring transitions for launcher, Spotlight, Downloads and Task Manager panels; smoother close
  and minimize animations.
- Full animation upgrade: stable dock item identity with add/remove/reorder transitions, icon bounce
  on launch, press ripple, cursor-following glass reflection, spring snap/minimize/restore, wallpaper
  fade, glass control centre, context menu and notification transitions, workspace sweep.
- `APLiteAnimation` centralises timing and honours system Reduce Motion plus an APLite switch;
  ripple count is capped and every effect clears itself (no leaks).
- Release channel metadata cleared: this is the stable 1.1.0, not a beta.

### Verification

- macOS CI build and packaging; see workflow run attached to the v1.1.0 tag.

## 1.1.0 (beta 1) — aplite-dev

### Added

- **Saved login cookies (vault):** imported cookies and cookies captured from WebKit are persisted
  in `cookies.json` under Application Support, restored at launch, listed per domain in Settings,
  exportable as JSON and removable per domain. New buttons: *Save login cookies* and *Export saved…*.
- **App open/close animation:** new windows spring in, closing windows shrink away, dock icons scale
  in/out, and minimizing animates opacity/size.
- **Cookie import** in Settings → Cookies from Safari: paste a `Cookie:` header / `document.cookie`
  from Safari's Web Inspector for a domain, import a Netscape `cookies.txt` from Files, or clear
  cookies for a domain. Cookies are installed into the shared `WKHTTPCookieStore`, so every APLite
  window sees them. iOS sandboxing prevents reading Safari's jar directly; the UI says so and never
  sends values anywhere.
- **Configurable screen saver**: 1/2/5/10/15/30/60-minute or never, three styles (drifting clock,
  APLite gradient, blurred wallpaper), motion on/off (burn-in protection) and 0.2–2 s fade.
- Vietnamese/localisable strings for the new settings.

### Changed / improved

- Performance: dock geometry (`taskLayout`) is computed once per redraw instead of three times,
  window-preview hit testing no longer walks the dock on every pointer move outside the taskbar,
  and the shortcut list (`items`) is cached and invalidated only when apps/bookmarks/web apps/user
  defaults actually change.
- Fixed the text-replacement separator sent from the Settings page (`\u0001` now reaches Swift as
  the intended control character).
- Visual polish: mesh-light gradient wallpapers, glass highlight on the dock pills, gradient title
  bars with a focused accent line, and a refreshed APLite-accented Settings page with responsive
  cards and buttons.

### Verification

- Same macOS CI process as 1.0.0; see the workflow run attached to this commit. No on-device
  cookie-import test is claimed.

## 1.0.0 (aplite-dev)

### Added

- APLite identity: `APLite` / AirPlayLite, new app icon, launch mark and background, accent colour,
  new built-in app icons and six new default wallpaper palettes.
- `APLite.swift` with the required attribution, upstream link and configurable repository keys.
- About screen on the iPhone and an About section in the desktop Settings page, both showing the
  original iDesk attribution verbatim.
- Floating Liquid-Glass dock: centred app icons with hover magnification, running/active
  indicators, dark/light/auto appearance, and separate glass pills for controls and the tray.
- Live dock settings: dock size, icon size, icon spacing, glass opacity, magnification and
  appearance; auto-hide was kept from upstream.
- Wallpaper blur and "Choose a picture from Files…" (Photos import was inherited from iDesk).
- `scripts/generate_assets.py` to regenerate bundled raster assets without network access.
- `APLite_AUDIT.md`, `BUILD.md`, `NOTICE.md`; build workflow renamed to APLite with an explicit
  `APLite-unsigned.ipa` artifact.

### Changed

- All user-visible "iDesk" text, permission descriptions, update messages and localised strings now
  say APLite; `Localizable.xcstrings` and `InfoPlist.xcstrings` were updated in step.
- Target, scheme, display name and marketing version updated in `project.yml`; the generated
  Xcode project remains `APLite.xcodeproj` with source folder `iDesk/`.
- Update checker and compatibility list now use the APLite repository from Info.plist instead of
  the upstream repository.
- Guest Engine files were not modified.

### Preserved (intentionally unchanged)

- Bundle identifier `com.hieuk.idesk`, signing/entitlements, UserDefaults keys, guest bundle
  prefixes, file names and notification names — to keep upgrades and guest apps working.
- Original LICENSE, copyright and attribution (see `NOTICE.md`).

### Verification

- Static checks in the development container: YAML/JSON/plist parsing, asset validation, shell
  syntax and source-hit-test consistency (model and view share the same rects).
- GitHub Actions `Build APLite` run `44985429096` on `macos-15` built successfully from
  `aplite-dev` and uploaded `APLite-unsigned.ipa` (2,412,749 bytes).
- The IPA was unpacked and checked: `Payload/APLite.app`, `CFBundleDisplayName = APLite`,
  `CFBundleName = APLite`, `CFBundleShortVersionString = 1.0.0`, bundle id unchanged, branded
  launch screen and repository keys present.
- No simulator or on-device test was performed; no signed IPA was produced (no certificate).

## Upstream

Upstream release notes live at https://github.com/itshieuk/iDesk/releases.
