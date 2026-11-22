# Independence from iDesk — separation status

APLite is based on iDesk by itshieuk. The attribution stays in `APLite.swift`, `NOTICE.md`,
`LICENSE`, README and every release note. This document tracks the **technical** separation only.

## Done

- All new APLite subsystems live in `APLite/System/` with a one-way dependency:
  Settings, Security, Power, Memory, Certificates, Files, Windows, Build Center, App Creator.
- `APLiteSettings` owns the ten user-facing setting groups under `APLite.*` keys; legacy `iDesk.*`
  keys are read-only compatibility for old installations.
- The internal API is a set of module facades (`WindowCoordinator`, `CertificateManager`,
  `PowerManager`, `BuildCenter`, `AppCreator`). Desktop/Controller code calls them; they do not
  own desktop UI except for their own SwiftUI sheets.
- Guest Engine files are untouched (except typed P12 error handling in the certificate importer).

## Still shared during transition (deliberate)

- The source folder was renamed `iDesk/` → `APLite/` in 1.2.5. The ObjC bridging header was renamed
  with it; bundle paths, guest bundle prefixes and persistence keys are intentionally unchanged.
- `DesktopModel` still owns legacy desktop state; new features call it through facades instead of
  writing its internals directly.
- UserDefaults keys starting with `iDesk.` are preserved so upgrades keep settings.
- Browser/WebKit, window drawing and input handling remain in `Desktop/` and `Controller/`.

## Next steps (not yet done)

1. Move the remaining Settings page actions out of the single `DesktopPages.handle` switch into
   per-group handlers.
2. Introduce an `APLiteKit` package boundary with explicit protocols for windows and files.
3. Migrate the browser storage to `APLite.*` keys with a one-time import from `iDesk.*`.

Nothing is deleted until the replacement module is compiled and tested.
