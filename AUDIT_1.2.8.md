# APLite 1.2.8 — Phase 0/1 audit & implementation record

Date 2026-11-23 · Base v1.2.7 (`7b595d9`) · branch `fix/1.2.8-patch-release`.
Static review only in this Linux container; build/test evidence comes from GitHub Actions.

## Task Skills (Phase 0)
No dedicated "Task Skills" existed in this OpenCode agent. Installed the public `chaunsin/agent-skills`
set **globally outside the repository** at `~/.config/opencode/skills/`: `to-task` (task decomposition),
`git-stack` (commit/push workflow), `pre-release-review` (release audit). Their workflows were used for
planning, staged commit hygiene and release validation. No skill file is tracked by Git, staged, pushed
or packaged into the IPA. The Copilot/VS Code skills present on the machine belong to a different agent
and were not used.

## Architecture (unchanged)
Two scenes: `PhoneSceneDelegate` (iPhone controller) and `ExternalSceneDelegate` (desktop on external
display). `DesktopModel` singleton owns windows, geometry and synthetic hit testing; the external scene
receives no touches, so every control is hit-tested with CGRects in `DesktopModel`. `DeskWindow` owns
WKWebView tabs; `WebViewHost` only displays existing web views. Guest Engine runs in-process and is
kept byte-for-byte compatible. Unsigned IPA via `xcodegen` + `xcodebuild CODE_SIGNING_ALLOWED=NO`.

## Confirmed working
Two-scene split, guest projection, real Safari UA + shared process pool, one-retry WebContent recovery,
account cookie vault, session restore, audio session manager with interruption/route recovery, bounded
caches/diagnostics, attribution, 1.2.7 UA/colour/Trash/zoom fixes.

## Root-cause findings fixed in 1.2.8
| Area | Finding → cause → fix |
|---|---|
| Browser | Popup configurations from WebKit received only UA/pool/desktop mode, losing media flags, scripts and bridges → one `applyBrowserPolicy(to:)` helper used for tabs and popups; content-blocker race closed; OAuth/popup tabs exempt from discard; stale zoom/gamepad IDs cleared; download resume no longer uses a foreign tab. |
| Audio | Guest audio killed by idle timer because `isShown` was used as "silent" → any live guest window keeps the session. Guest `setCategory` changes were unobserved → route-change `.categoryChange` + 20 s tick repair. Voice typing had no interruption observer → stops cleanly on `.began`. `pending` JS Set leaked media elements → delete on early return. "Mute" tile mislabelled a volume-zero reading → relabelled. |
| Diagnostics | Data existed in 12 files with no aggregation, error history or repair/re-check loop → new read-only `DiagnosticsPolicy` + `TechnicalDiagnosticsView`, view-scoped responsiveness probe, safe repairs with confirmation. No CPU% claim (public iOS API does not expose it). |
| Settings | Flat sections with no icons, two visual languages, forced dark everywhere, no confirmations → section icons from existing (previously unused) `SettingsGroup.symbol`, `.insetGrouped`, optional Light appearance for the native stack, confirmation alerts. |
| Windows | Fullscreen/maximize state changes sat outside `withAnimation`; traffic lights mixed fixed red with dynamic yellow/green; pin badge overlapped tabs; PiP used the maximize glyph → geometry animated, one fixed palette, pin moved, PiP glyph fixed, WebApp zoom buttons with current level. |
| Trash | Bundled guest with pending update was "deleted" then reappeared (its Documents copy was gone); `toggleRemoval` could silently unmark; Trash icon could be hidden (disabling drag-to-trash); stale zoom/closed entries after WebApp removal → bundled guests always marked, idempotent `markForRemoval`, Trash protected, WebApp restore from desktop menu, zoom/undo cleanup. |
| Performance | Cookie vault rewritten on every identical sign-in burst (signature was write-only) → `force` flag, automatic path dedupes; per-tab zoom entries leaked on window close → cleanup in `deinit`. |
| Evidence hygiene | Test plan asked for a UA that "contains only" two tokens; release notes claimed fixed red on every appearance → wording corrected; `redOnGlass` doc still inaccurate for alpha call sites (tracked as remaining issue). |

## Compatibility red lines preserved
Bundle id `com.hieuk.idesk`; all `iDesk.*`/`APLite.*` keys, `idesk://`, `iDeskGuest_*`, launch args;
LICENSE/NOTICE/attribution; unsigned build path; Guest Engine behavior. No native iOS app uninstall,
no engine spoofing, no Service Worker/WebAuthn claim.

## Remaining / BLOCKED
- Gmail banner and UA token placement need on-device confirmation; Windows/WebKit feature-gated checks may still show it. BLOCKED without hardware.
- Service Workers, WebAuthn/passkeys in embedded WKWebView, Chrome engine: BLOCKED by iOS/WebKit.
- Per-app CPU% and other processes' logs: BLOCKED by iOS sandbox; diagnostics uses proxies.
- `redOnGlass` + `.opacity()` still shifts on the light dock; needs device check and one appearance-specific palette (not changed blindly in this patch).
- Guest watchdog event-driven replacement and staggered WebContent reload were assessed; kept the safer existing behavior to avoid regressions.
