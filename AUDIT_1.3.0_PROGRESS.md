# APLite 1.3.0 — implementation progress (phases 0–4)

Companion to `AUDIT_1.3.0_PHASE0.md`. Read that first for the preservation baseline.

## Verification caveat (applies to every phase below)

No Xcode/Swift/UIKit/Simulator in this container. Local verification was **static only**:
balanced delimiters on every edited Swift file, JSON parsing for `Localizable.xcstrings` and
`Assets/registry.json`, existence checks for all referenced licence/library paths, glyph-existence
checks for all 42 registry concepts, and `git check-ignore` to confirm the asset library is not
dropped. **No compile, unit-test or on-device claim is made.** CI is the gate.

## Phase 0 — Preservation ✅

Documented in `AUDIT_1.3.0_PHASE0.md`. No stash/reset/rebase; all pre-existing uncommitted work
(the previous session's boot wiring) was reviewed and preserved.

## Phase 1 — Boot Screen ✅ (static gate only)

- `APLite/App/BootExperience.swift` — reviewed and hardened the existing `BootCoordinator`:
  - Added a **20 s per-step watchdog** (`DispatchWorkItem`) — a stuck service now surfaces the
    error/retry UI instead of stranding the user. Progress remains **event-driven**; there is no
    fake delay used to make the animation look longer.
  - A late step completion after a watchdog failure is ignored, so a timed-out startup cannot
    resume behind the error screen.
  - Centralised `finishServices()` / `fail()` / `armWatchdog()` / `cancelWatchdog()`; no duplicate
    service initialisation (verified: each service's `start()` appears exactly once).
  - Error text and all phase labels are localised in `APLite/Localizable.xcstrings` (EN + VI).
- Flow preserved: services ready → external scene calls `externalConnected()` → `lockDesktop` when
  configured → `finishDesktopPreparation()` → desktop. `lockDesktop(force: true)` is correct here
  because `externalConnected()` sets `isExternalConnected` first.
- Returning from background does not replay boot: `desktopReady`/`servicesReady` are sticky in the
  singleton, and the external scene removes its observer on disconnect (no listener leak).

## Phase 2 — Asset System ✅

- Full licensed source library at `Assets/Icons/`: Tabler Icons 3.52.0 (5,491 outline + 1,054
  filled SVGs, MIT) and Lucide Icons (2,104 SVGs, ISC). Original `LICENSE` files kept verbatim.
- `Assets/registry.json` — machine-readable manifest with versions, licences, paths, wallpapers
  and 42 verified cross-family concepts.
- `Assets/ATTRIBUTION.md` + a short addition to `NOTICE.md` — attribution preserved.
- `APLite/System/AssetRegistry.swift` — native registry. Views still use SF Symbols; nothing in
  `Assets.xcassets` or any existing view was replaced.
- Per the agreed choice, **Meadow/Ocean wallpapers are unchanged** and only catalogued in the
  registry. Library sits outside `APLite/`, so XcodeGen will not bundle it; no runtime hotlinking.

## Phase 3 — Design System foundation 🟡 (foundation only)

- `APLite/System/APLiteDesign.swift` — one token set (spacing, radius, type, surface, touch target).
- Boot screen migrated to those tokens; `APLiteGlassButtonStyle` now uses `Radius.sm` (same 12 pt
  value, no visual change).
- **Not done:** the broad redesign of Desktop, dock, Start Menu, Settings, window chrome, context
  menu, notifications, App Center and dialogs. Doing that blind — without a build — would risk the
  1.2.9 stability the brief puts above visual effects. `UI_SYSTEM_PLAN.md` records the per-surface
  token mapping and the one-surface-per-commit order for that work.

## Phase 4 — 1.3.5 readiness ✅

No speculative 1.3.5 feature was added. The seams that exist are the ones 1.3.0 genuinely needs:
a single boot coordinator, a single design-token file and a single asset registry. No new
abstraction layer was introduced beyond those.

## Files changed in this session

| File | Change |
| --- | --- |
| `APLite/App/BootExperience.swift` | new (from previous session) + watchdog/hardening + tokens |
| `APLite/Localizable.xcstrings` | boot strings + timeout string (EN/VI) |
| `APLite/System/APLiteDesign.swift` | new — design tokens |
| `APLite/System/AssetRegistry.swift` | new — native asset registry |
| `APLite/System/APLiteGlass.swift` | radius literal → token |
| `Assets/registry.json`, `Assets/ATTRIBUTION.md`, `Assets/Icons/**` | new — licensed asset library |
| `NOTICE.md` | third-party attribution note |
| `AUDIT_1.3.0_PHASE0.md`, `AUDIT_1.3.0_PROGRESS.md`, `UI_SYSTEM_PLAN.md` | new — audit/plan records |

Pre-existing uncommitted changes to `AppDelegate.swift`, `SceneDelegates.swift`, `DesktopView.swift`
and `.gitignore` were left in place (reviewed, not rewritten). `skills-lock.json` remains untracked;
the skill directory itself is gitignored and is not bundled.

## Open items / gates before calling 1.3.0 complete

1. **CI build + unit tests** — mandatory; not possible here.
2. **On-device boot flow**: cold launch with/without external display, lock-on-launch on/off,
   background→foreground (boot must not replay), display disconnect→reconnect, simulated slow
   service to exercise watchdog + retry.
3. **The broad UI pass** in `UI_SYSTEM_PLAN.md`, one surface per build.
4. **Version metadata** deliberately left at `1.2.9` (`project.yml`, changelog, README, live
   manifest, in-app changelog) so an unverified build is never labelled 1.3.0. Bump all of them
   together only after items 1–3 pass.
5. Decide whether to commit `skills-lock.json` (pins the design-skill version; contains no skill
   content). It was left untracked pending your preference.
