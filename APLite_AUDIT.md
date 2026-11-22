# APLite — Source Code Audit

Audit date: 2026-11-22
Upstream: https://github.com/itshieuk/iDesk — commit `2179dbd` (tag `v0.6.3`)
Imported into APLite in commit `11aea86` on branch `aplite-dev`.

This document was written **before** the redesign. It records what the imported source does and
what APLite changed. It is intentionally conservative: the Guest Engine (IPA loading, Mach-O
patching, UIKit hooks) was not rewritten.

## 1. Current architecture

The app is a UIKit application with a SwiftUI interface, generated from `project.yml` by XcodeGen.
There are two scenes:

| Scene | Delegate | Purpose |
| --- | --- | --- |
| Phone (`.windowExternalDisplayNonInteractive` is the other role) | `PhoneSceneDelegate` | Trackpad / keyboard / input sheets on the iPhone |
| External display | `ExternalSceneDelegate` | `DesktopView` on the monitor or TV |

`AppDelegate` installs the crash reporter, starts mouse / controller / media input and the update
checker, and enables battery monitoring. `PreviewController` runs the same `DesktopView` on the
iPhone for development (`-iDeskPreview`).

The desktop is a single `@ObservedObject DesktopModel` (shared singleton) with a self-drawn
pointer. The external display receives no real touches, so `DesktopModel` owns hit testing, window
dragging/resizing and synthetic events. `CursorModel` is deliberately separate so pointer motion
does not redraw the whole desktop.

## 2. Important modules

| Folder | Role |
| --- | --- |
| `App/` | Application and scene lifecycle, external display resolution, update checks, own-bundle detection |
| `Desktop/` | Desktop model, windows, taskbar/dock, browser, Files, widgets, wallpaper, spotlight, clipboard, screenshots, remote display |
| `Controller/` | iPhone trackpad, key capture, settings/welcome/apps sheets, system photo/document pickers |
| `Input/` | GameController mouse, keyboard and input helpers |
| `Guest/` | IPA import, Mach-O patching, code signing, guest runtime (ObjC), shims, synthetic touches and crash reporting |

Key files:

- `Desktop/DesktopModel.swift` (~3.4k lines): all desktop state, geometry, hit testing, persistence.
- `Desktop/DesktopView.swift` (~1.6k lines): wallpaper, windows, taskbar, panels, icons.
- `Desktop/DeskWindow.swift`: a window (browser tabs, own page or guest app) and its WebKit bridges.
- `Desktop/DesktopPages.swift`: HTML Settings/Apps/History pages and their action handler.
- `Guest/GuestRuntime.m`, `GuestShims.m`, `GuestTouch.m`: loaded app lifecycle, process-wide hooks and touches.
- `Guest/MachOPatcher.swift`, `GuestStore.swift`, `CodeSigner.swift`: IPA pipeline.

## 3. Dependencies and relationships

- no Swift Package dependencies; no submodules; no Git LFS.
- SwiftUI + UIKit + WebKit, PhotosUI, UniformTypeIdentifiers, GameController, QuartzCore.
- Objective-C guest code is exposed through `iDesk-Bridging-Header.h` (kept under the original
  `iDesk/` source folder so the bridge and bundle paths stay valid).
- `DesktopModel` observes `GuestStore`, `Browsing`, `ContentBlocker`, `UpdateChecker` and several
  observers/DispatchWorkItems. `Bundle.iDesk` resolves the real app bundle because `Bundle.main`
  is temporarily swapped while a guest app runs.

## 4. Working functionality observed in source

- Window manager: move, resize, minimize, maximize, snap layouts, workspaces, keep-on-top,
  session restore.
- Browser: tabs, bookmarks/history, ads blocker, downloads, fullscreen video, find, zoom, reader.
- Own pages: Files, Settings, Apps, Bookmarks/history, text editor.
- Desktop: icons, widgets, sticky notes, dynamic/gradient/photo wallpapers, lock, screen saver,
  night filter, screenshots, clipboard history, spotlight.
- Input: trackpad gestures, pointer, GameController/AssistiveTouch mouse, Bluetooth keyboard,
  synthetic touches into guest apps.
- Guest Engine: IPA unpack → Mach-O thin/patch → store → ESign packaging → `dlopen` → lifecycle
  and touch injection → crash diagnostics. **Left unchanged.**
- Remote browser display over Wi-Fi and AirPlay-style laptop mode.

## 5. Identified issues (before APLite changes)

1. The taskbar was a full-width, opaque `.ultraThinMaterial` rectangle pinned to the bottom. App
   entries were left-aligned after the launcher/navigation/workspace controls; there was no centred
   dock and no floating glass treatment.
2. The taskbar's height was hardcoded as `Layout.taskbar = 48` while several controls used
   `taskbarTop + 4`; changing one metric required touching both the model and the view.
3. Taskbar settings were limited to auto-hide. Size, icon size, spacing, transparency, magnification
   and appearance were not adjustable.
4. Wallpaper had gradient, dynamic and photo modes with persistence, but no Files import, no blur
   control and no APLite-branded default set.
5. Settings and About identified the product as iDesk; the original attribution was not present in
   the app itself.
6. `taskLayout` silently dropped items that did not fit; the model and the SwiftUI view used the
   same `Layout` constants, so a future change to only one side could desynchronise them.
7. CI built `iDesk.ipa` on pushes to `main` only, with no clear unsigned-artifact name.

## 6. Crash / instability risks (assessed, not "fixed blindly")

- Guest apps share the host process: a hang or crash in a guest takes down the host. Mitigated
  upstream by `CrashReporter`, memory warnings, and not reopening apps after an abnormal exit.
- `GuestShims.m` hooks are process-wide; the upstream code already partitions them per app. APLite
  does not modify those files.
- `taskbarTop` / `desktopArea` are derived from `screenSize`; a resolution change while windows are
  open calls `fitWindowsToScreen()`. The new dock keeps the same band height, so this path was not
  changed.
- DispatchWorkItems (toast, banner, task preview, save) capture `[weak self]` where relevant; no
  new long-lived captures were introduced by the dock.
- `setCustomWallpaper` resizes before saving (max side 2560) to bound memory. The new Files import
  reuses the same path rather than loading a full-resolution image into the UI.

## 7. Files expected to change (and changed)

- `project.yml`, `iDesk/Info.plist`, `InfoPlist.xcstrings`, `Localizable.xcstrings` — product name,
  version, launch screen, repository configuration, user-visible strings.
- `iDesk/Desktop/DesktopModel.swift`, `DesktopView.swift`, `DockSettings.swift` — dock geometry,
  floating glass taskbar, wallpaper blur and Files import.
- `iDesk/Desktop/DesktopPages.swift`, `Downloads.swift`, `ScreenRecorder.swift` — dock settings UI,
  rects inside the right pill.
- `iDesk/Controller/SystemSheets.swift`, `SettingsSheet.swift`, `AboutView.swift` — typed document
  picker, About screen.
- `iDesk/App/APLite.swift`, `UpdateChecker.swift`, `Guest/Compatibility.swift`,
  `Desktop/DesktopModel.swift` — attribution and update/repo links.
- `iDesk/Assets.xcassets/` — new app icon, launch mark/background, accent colour, built-in icons.
- `scripts/build-ipa.sh`, `.github/workflows/build.yml`, `release.yml` — APLite build and artifacts.
- `README.md`, `BUILD.md`, `CHANGELOG.md`, `NOTICE.md` — documentation.

## 8. Repair / upgrade plan

1. Rebrand without touching persistence keys, bundle id, bridging header or guest identifiers.
2. Rebuild the taskbar as three floating glass pills with model-owned geometry (done); keep all
   existing click actions and keyboard/pointer hit testing.
3. Add live dock customisation and wallpaper blur/Files import through the existing Settings page
   state/action pipeline (done).
4. Generate all raster assets locally and commit them; no network fetch at launch (done).
5. Keep the Guest Engine byte-for-byte unchanged; update only APLite-facing strings and repo links.
6. Build on macOS via GitHub Actions; the Linux development container has no Xcode/Swift/UIKit, so
   compilation and device testing are reported from CI only, never claimed locally.

## Out of scope / not claimed

No device testing, no Guest Engine overhaul, no signed IPA (no certificate is configured), and no
verification of input/display behaviour on real hardware was possible in this environment.
