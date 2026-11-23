# APLite 1.3.0 — unified UI system (Native SwiftUI translation)

This maps the design skill's "one system" rule onto APLite's **native** surfaces. The skill itself
is a browser/DOM tool and its gate, shaders and CSS are deliberately **not** used here; only its
design principles are translated. Tokens live in `APLite/System/APLiteDesign.swift`; motion lives
in `APLite/App/APLiteAnimation.swift`; semantic colour lives in `APLite/System/APLiteColors.swift`.

## Tokens (single source)

| Role | Token | Value |
| --- | --- | --- |
| Boot ground | `Surface.bootBackground` | deep flat navy, no blur |
| Accent | `Surface.bootGlow` → `APLiteColors.accent` | `#38BDF8`, sRGB-pinned |
| Text | `Surface.primaryText / statusText / secondaryText` | white at 1 / .76 / .62 |
| Spacing | `Space.xs…xxxl` | 6, 10, 14, 16, 20, 24, 28 pt |
| Radius | `Radius.sm / md / lg` | 12, 16, 22 pt (continuous) |
| Type | `Typography.display / title / body / caption` | one scale, system rounded display |
| Touch | `touchTarget` | 44 pt |
| Motion | `APLiteAnimation.{gentle, snappy, spring, dock}` | reduced-motion aware |

## Per-surface state

| Surface | Owner | 1.3.0 state | Next action (requires CI build) |
| --- | --- | --- | --- |
| Boot screen | `App/BootExperience.swift` | **Tokenized**, event-driven, watchdog, retry | Verify on device at phone + external sizes |
| App window chrome / title bar | `Desktop/DesktopView.swift` | Unchanged — already uses one chrome/focus-ring system from 1.2.8 | Adopt `Radius.sm` only where literal radii diverge; no structural change |
| Dock / taskbar | `Desktop/DesktopView.swift` | Unchanged — 1.2.9 geometry is unit-tested | Do not resize without re-running window-list tests |
| Start menu / Launcher, Spotlight | `Desktop/DesktopView.swift` | Unchanged | Reuse `.floatingPanel` + one scale; audit spacing |
| Settings (native + desktop HTML) | `System/SystemSettingsView.swift`, `Desktop/DesktopPages.swift` | Unchanged — keys and actions preserved | Replace scattered literals with tokens incrementally |
| Context menu / notifications | `Desktop/DesktopView.swift`, `DesktopModel.swift` | Unchanged | Reuse `APLiteGlassButtonStyle` and `Radius.sm` |
| App Center | `Desktop/DesktopPages.swift` | Unchanged | Keep WebApp identity/zoom logic intact |
| Dialogs / status screens | various | Boot error/retry is the only new one | Adopt the same error/retry treatment when touching each screen |

## Rules for the next pass

1. Change **one** surface per commit, build it, then continue. Never batch a whole-system rewrite.
2. Prefer replacing a literal with a token (no visual change) over inventing a new look.
3. No violet/lavender, no tilt, no scroll-linked motion, no fade-in on every panel.
4. Keep blur/shadow at today's level; the external display scene has no touches and is GPU-bound.
5. Every control stays ≥ 44 pt and works with both the self-drawn pointer and touch.
6. Keep `Reduced Motion` and `Performance mode` behaviour: `APLiteAnimation.reduced` must still
   collapse every new animation to an instant state change.

Nothing above was applied to legacy surfaces in this phase. That is intentional: preserving the
1.2.9 build is higher priority than an unverifiable visual rewrite.
