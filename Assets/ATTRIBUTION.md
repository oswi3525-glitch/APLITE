# Third-party asset attribution

These assets are kept as a **local source library** at the repository root. They are not part of
the `APLite/` application source folder and are not copied into the app bundle. Nothing is loaded
from a remote URL at runtime (no hotlinking).

## Tabler Icons

- Version: 3.52.0
- Source: https://github.com/tabler/tabler-icons
- License: **MIT** — full text in `Assets/Icons/Tabler/LICENSE`
- Attribution: Copyright (c) 2020-2026 Paweł Kuna
- Contents: `Assets/Icons/Tabler/outline/` — the 42 glyphs referenced by APLite's native registry.
  The full upstream set (5,491 outline + 1,054 filled) remains available from the source URL.

## Lucide Icons

- Source: https://github.com/lucide-icons/lucide
- License: **ISC** — full text in `Assets/Icons/Lucide/LICENSE`
- Attribution: Copyright (c) 2026 Lucide Icons and Contributors
- Contents: `Assets/Icons/Lucide/icons/` — the same 42 registry glyphs. Upstream metadata JSON was
  dropped to keep the library small (2,104 SVGs in the full upstream set).

## APLite-owned assets

- `MeadowWallpaper` and `OceanWallpaper` are generated locally by
  `scripts/generate_meadow.py` and `scripts/generate_ocean.py`. No external photograph or
  third-party photo licence is involved.
- `AppIcon`, `LaunchMark`, `LockMark`, `FilesIcon`, `SettingsIcon`, `TrashIcon`, `BrowserIcon`,
  `FacebookIcon`, `ZaloIcon`, `TelegramIcon` and `AccentColor` remain in `APLite/Assets.xcassets`
  unchanged. They are managed by the existing asset catalog, not by this library.

## Registry

`Assets/registry.json` is the machine-readable manifest. `APLite/System/AssetRegistry.swift` is the
native (SwiftUI-facing) registry. A concept listed there was verified to exist by name in **both**
icon families, so a family swap does not require editing individual views.

SVGs are stored as distributed upstream (already compact). Do not re-add the same source under a
second path; add new assets to the manifest and this file instead.
