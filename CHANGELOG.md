# Changelog

All notable changes to APLite are documented here. APLite is based on iDesk v0.6.3
(upstream commit `2179dbd`); the original upstream history is not rewritten.

## 1.1.0 (aplite-dev)

### Added

- **Cookie import** in Settings → Cookies from Safari: paste a `Cookie:` header / `document.cookie`
  from Safari's Web Inspector for a domain, import a Netscape `cookies.txt` from Files, or clear
  cookies for a domain. Cookies are installed into the shared `WKHTTPCookieStore`, so every APLite
  window sees them. iOS sandboxing prevents reading Safari's jar directly; the UI says so and never
  sends values anywhere.
- **Configurable screen saver**: 1/2/5/10/15/30/60-minute or never, three styles (drifting clock,
  APLite gradient, blurred wallpaper), motion on/off (burn-in protection) and 0.2–2 s fade.
- Vietnamese/localisable strings for the new settings.

### Changed / improved

- Performance: dock geometry (`taskLayout`) is computed once per redraw instead of three times, and
  window-preview hit testing no longer walks the dock on every pointer move outside the taskbar.
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
