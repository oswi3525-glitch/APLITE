# APLite architecture audit & module separation plan

Audit date: 2026-11-22. Source: `fix/audio-and-hardening` (after the audio repair commit `20d413a`).
This document is the plan for turning APLite into an independent desktop environment **without**
rewriting the app or breaking the Guest Engine.

## 1. What exists today (measured from source)

| Area | Owner today | Lines | Notes |
| --- | --- | --- | --- |
| App / scenes | `App/AppDelegate.swift`, `SceneDelegates.swift` | ~170 | Two scenes (iPhone controller, external desktop). Crash reporter, input, audio, update checker start here. |
| Desktop state | `Desktop/DesktopModel.swift` | 3,664 | One singleton owns windows, geometry, hit testing, persistence, settings state and notifications. |
| Desktop UI | `Desktop/DesktopView.swift` | 1,948 | Wallpaper, windows, dock, quick panel, overlays. Draws lock/screensaver. |
| Lock | `Desktop/LockScreen.swift` | 214 | `LockSettings` (UserDefaults), LocalAuthentication biometrics, screen saver, lock views. **No passcode of its own.** |
| Files | `Desktop/FileStore.swift`, `FilesExtras.swift` | 760 | HTML-based Files page, cut/paste, downloads. No size columns, folder totals or dedicated APLite area. |
| Memory | `Desktop/NetworkStatus.swift` (`MemoryStatus`) | 28 | `phys_footprint`, `os_proc_available_memory`, simple low/critical levels. No peak, no 1 GB target, no leak detection. |
| Tasks | `Desktop/TaskManager.swift` | 156 | Window list + memory string + close/minimize all. |
| Signing | `Guest/SigningStore.swift`, `Guest/CodeSigner.swift` | 561 | P12 in Keychain, `SecPKCS12Import`, one generic `.badCertificate(String)` error. `.pfx` not explicitly recognised; error cases not typed. |
| Settings | `Desktop/DesktopPages.swift` | 1,000+ | One HTML page, flat key/value state, ~70 actions in one `switch`. No grouped/professional layout. |
| Guest Engine | `Guest/*.m`, `MachOPatcher.swift`, `CodeSigner.swift`… | — | **Must stay compatible. No changes in this phase.** |
| Audio | `App/AudioSessionManager.swift` | 251 | Single session owner, interruption/route handling, diagnostics. |

## 2. Constraints that shape the design

1. **iOS cannot unload code.** "Shutdown" means closing APLite surfaces and suspending guest apps
   (`GuestRuntime.suspendAppWithWindow:`); it does not quit the process or power off hardware.
2. **No entitlement for other apps' sandboxes.** The APLite file area is under our Application
   Support directory; we never read another app's container.
3. **Xcode does not run on iOS.** A Build Center may analyse projects and talk to a macOS worker
   via GitHub Actions; it must never pretend a local build happened.
4. **Secrets in Keychain only.** Passwords and private keys are never written to UserDefaults,
   diagnostics, `NSLog`, `os_log` or crash reports.
5. **Memory is a soft limit.** iOS decides the real limit; a 1 GB *target* means proactive release
   and warnings, not a hard cap we can enforce.

## 3. Target module layout (additive; nothing deleted)

```
iDesk/System/                 ← NEW: APLite-owned, independent of iDesk UI
  APLiteSettings.swift        typed settings, 10 groups, persisted, migration-safe
  SecurityManager.swift       passcode (Keychain), throttle, biometrics, lock policy
  PowerManager.swift          shutdown / sleep / wake state machine + persistence
  MemoryManager.swift         1 GB target, peak, warnings, leak heuristics, release
  CertificateManager.swift    P12/PFX import, typed errors, no secret logging
  APLiteFileManager.swift     APLite file area, metadata, sorting, folder totals
  WindowCoordinator.swift     internal API façade over DesktopModel windows
  BuildCenter.swift           project analysis + GitHub Actions worker client
iDesk/App/                     existing app lifecycle, audio, icons
iDesk/Desktop/, Controller/    existing UI, gradually calling System/
Guest/                         UNCHANGED (compatibility preserved)
```

An internal **module API** is just a set of public-on-module singletons/value types under `System/`.
Desktop and Controller code call them; they never call back into `DesktopModel` except through
`WindowCoordinator`, so the dependency direction is one-way and the old code keeps working.

## 4. Implementation order (each step compiled/tested before the next)

1. **Security** — lock on launch, passcode create/change/verify in Keychain, throttle, sleep/wake hooks.
2. **Power** — shutdown/sleep/wake, close guest windows, save/restore state, cancel background work.
3. **Memory** — 1 GB target, live/peak display, warnings, cache release, leak heuristic.
4. **Certificates** — P12/PFX typed errors via `SecPKCS12Import`, safe storage.
5. **Files** — APLite area, sizes/metadata/sorting/preview, multi-window support.
6. **Windows** — coordinator façade, snap/order/restore improvements.
7. **Settings** — grouped desktop-style layout using the new modules.
8. **Build Center** — real local analysis + honest GitHub worker integration.
9. **UI/animation** — unified Liquid Glass, remove unintended circular press effect.
10. **Testing/CI** — unit tests per module, IPA artifact, unresolved-issues report.

## 5. Verification policy

- Every module gets unit tests for its **pure logic** (validation, state machines, formatting) in
  `APLiteTests`. UI and Keychain behaviour is listed in an on-device checklist.
- macOS CI builds the IPA and runs the tests. Linux container results are static checks only.
- Nothing is marked complete until its tests and the on-device checklist are done.
