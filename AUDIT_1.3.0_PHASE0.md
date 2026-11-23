# APLite 1.3.0 — Phase 0 preservation audit

Scope: repository state *before* any 1.3.0 edit. This is the "Preserve" step of
**Preserve → Abstract → Replace → Verify**. It records what must keep working and
what is allowed to change.

## Environment constraint (read first)

The Linux container has **no Xcode, no Swift toolchain, no UIKit and no Simulator**
(`which swiftc` → empty; `node` v24 available). Therefore:

- No local build, unit-test run or on-device check can be claimed in this phase.
- Verification here is **static only**: source review, structural token/string
  balance, JSON catalog parsing and diff inspection.
- CI (`Build APLite` workflow) and `SYSTEM_TEST_PLAN.md` remain the source of truth
  for compile/build/device status. Nothing in this document says "build passes".

## 1. Git state at entry

| Item | Value |
| --- | --- |
| Branch | `fix/1.2.8-patch-release` |
| HEAD | `463e374 fix(build): 1.2.9 Window list private access and battery-state switch` |
| Nearest stable point | **1.2.9** (HEAD, latest changelog + release notes entry) |
| Tracked modifications | `.gitignore`, `App/AppDelegate.swift`, `App/SceneDelegates.swift`, `Desktop/DesktopView.swift`, `Localizable.xcstrings` |
| Untracked | `App/BootExperience.swift`, `skills-lock.json` |
| Interpretation | A previous session had already started the 1.3.0 Boot Screen wiring but had not committed it, built it or reported it. It is treated as in-progress user work: reviewed, preserved, then hardened — never overwritten wholesale. |

No stash/reset/rebase was performed. No existing skill or tool config was removed.

## 2. Working feature inventory (must not regress)

From `CHANGELOG.md` 1.2.4–1.2.9 and `ARCHITECTURE.md`:

1. Two-scene lifecycle: iPhone controller (`PhoneSceneDelegate`) + external
   display desktop (`ExternalSceneDelegate`), selected by scene role in `AppDelegate`.
2. Guest Engine / sideloaded apps (ObjC + `MachOPatcher`, `CodeSigner`) — **untouched**, compatibility is non-negotiable.
3. Pairing / connection: `MouseInput`, `ControllerInput`, `GuestRuntime` scene-event forwarding, external display attach/detach, Wi-Fi "laptop as display".
4. Window management: open/close/minimize/restore, tabs, find-in-page, snap/tile, fullscreen, PiP, drag-to-trash, saved session restore.
5. WebKit stack: shared process pool, real Safari UA, cookie vault + `AccountCookies` observer, browser policy helper, WebApp zoom, content blockers, clean Facebook layer.
6. Audio: single `AudioSessionManager` owner, activity tracking, Quick Look, read-aloud, Web Audio resume.
7. Settings: native `SystemSettingsView` + desktop HTML Settings, `APLiteSettings` typed keys, Advanced tools page (Build Center, certificates, Diagnostics).
8. Security: `SecurityManager`, lock-on-launch, lock-on-sleep/wake, `LocalAuthentication`.
9. Power: `PowerManager` shutdown/sleep/wake, clean-shutdown session persistence.
10. Memory/perf: `MemoryManager`, `CacheManager`, `ThermalMonitor`, widget cadences, bounded caches, reduced-motion/performance mode.
11. On-screen keyboard (draggable), Spotlight, Launcher, dock, taskbar/window list, notifications, context menus.
12. Localization: English source + Vietnamese `Localizable.xcstrings`.

## 3. Recorded performance constraints

- 1 GB memory **target**, not a hard cap (`MemoryManager`); peak/warnings/leak hints.
- WebKit/URL caches bounded and trimmed every 5 min; Quick Look decoded image released.
- Widgets tick at their own cadence; lock screen clock isolated from blurred wallpaper.
- Thermal state `fair`+ forces instant animations; `APLiteAnimation.reduced` also honours Reduce Motion.
- External display scene receives **no touches** — hit testing lives in `DesktopModel`, not SwiftUI buttons.
- Unlimited blur/shadow and page-wide repaints are known cost centers; do not add more.

## 4. Components most at risk during a UI pass

| Component | Why it is risky |
| --- | --- |
| `DesktopModel.swift` (~3.7k lines) | Single singleton owns geometry, hit testing, persistence, notifications. Most UI reads/writes it. |
| `DesktopView.swift` (~1.9k lines) | Wallpaper, windows, dock, overlays, lock/screensaver. Boot wrapper was inserted at the top of this file. |
| `SceneDelegates.swift` | Boot gating and lock-on-launch were moved here; changing order can double-init or lose the lock. |
| `AppDelegate.swift` | Service init order was replaced by `BootCoordinator` steps; `CookieVault.restore()` must stay before WebKit loads. |
| Guest Engine + `AppDelegate` bridging header | Any signature/entitlement/API change breaks sideloading. No changes permitted. |
| `Localizable.xcstrings` | New boot strings must keep the Vietnamese catalog complete. |
| `Assets.xcassets` | Existing icon/wallpaper images are in use; new assets must be additive. |

## 5. Design skill assessment (required by the brief)

Installed at `.agents/skills/design-taste-frontend/SKILL.md` (v2.5.1), gitignored via
`/.agents/skills/design-taste-frontend/`, `skills-lock.json` records the pinned commit.

It is a **website/DOM** skill (HTML/CSS/JS via headless Chrome, `gate.mjs`).
It does **not** support SwiftUI/UIKit, and its scripts (`gate.mjs`, `shoot.mjs`,
`perf.mjs`, GSAP/DOM techniques) are **not** applicable to APLite's native views.

Applicable principles, translated to native SwiftUI:

- One design system: single source for color, radius, spacing, typography, motion.
- One hero/entrance moment per screen; quiet micro-interactions; no scroll-linked motion.
- Reduced-motion must rest, never hide content.
- No violet/lavender in the product's own palette.
- Real, legible icons; flat, deliberate backgrounds; restrained blur/shadow on mobile.
- Equal content edges, consistent corner-radius scale, 44 pt touch targets.

Not applicable and therefore excluded: browser gate scripts, WebGL/shader scenes,
photo-chapters, CSS grounds, `data-*` markup, screenshots at 1440/1024/768/390.
Any WebApp HTML inside APLite remains a separate, explicitly scoped surface; no
native code imports browser techniques.

## 6. Phase gate for 1.3.0

Phase 0 → Phase 1 may proceed. Blocking rule from the brief: do not advance while
the current phase has a serious unresolved error. Compile/device verification is
delegated to CI; static checks are the only local gate available here.
