# APLite (AirPlayLite)

**A lightweight desktop for iPhone and iPad.** Connect your phone or tablet to a monitor or TV
(USB-C → HDMI/DisplayPort, or AirPlay to an Apple TV) and APLite gives the big screen desktop
windows, a floating Liquid-Glass dock, a browser, files, widgets and iOS apps in windows. The phone
becomes the trackpad and keyboard.

> Experimental: APLite uses private UIKit APIs, is meant to be sideloaded, and a future iOS may
> break parts of it. Latest unsigned build: **1.2.8** (CI build + unit tests passed; on-device
> verification is still pending).

## Attribution — original project

APLite is an independently developed project based on the original iDesk project by itshieuk.

Original project:
https://github.com/itshieuk/iDesk

APLite introduces independent design changes, improvements, modifications and additional features while acknowledging the original project’s author and contributors.

APLite is not an official release or endorsement of the original iDesk project.

The original MIT license and copyright notice are preserved in [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md).

## What APLite changes

- **Rebrand:** new name, app icon, launch screen, accent colour, built-in icons, wallpapers and
  in-app About with the upstream attribution above.
- **Floating dock:** app icons centred in a glass pill, separate glass pills for controls and the
  system tray, hover magnification, running/active indicators, dark/light/auto appearance. All
  buttons use the existing desktop logic — nothing is decorative.
- **Dock settings:** size, icon size, spacing, glass opacity, magnification, appearance and
  auto-hide, all live in Settings → Dock.
- **Wallpapers:** a new APLite default set, the bundled **Đồng cỏ** (meadow) and **Biển** (ocean)
  photos, photo import from Photos **or Files**, blur, persistence and per-workspace choices.
- **Analogue clock:** the desktop widget, lock screen, screen saver and quick panel show a drawn
  analogue clock (with a digital readout alongside).
- **Web apps:** Zalo, Facebook, Telegram, Chrome, YouTube and Gmail with branded icons are installed
  on first launch; native versions still require a decrypted IPA.
- **Cookies & saved logins:** sign-ins in any web window (including windows on the external display)
  are watched through WebKit's cookie store and copied into APLite's local vault automatically, with
  flushes on background, display disconnect and shutdown. You can also paste a `Cookie:` header for a
  domain or import a Netscape `cookies.txt` from Files; the vault is restored at launch and can be
  exported as JSON. iOS does not expose Safari's jar to other apps, so imported values are copied by
  you and stay on the device.
- **On-screen keyboard:** a full keyboard for the desktop can be enabled in Settings. It appears only
  when a text field is tapped, supports Shift / Caps Lock / symbol layers, arrows and editing keys,
  and has a hide key. A dedicated iPhone settings page lists every key.
- **Clean Facebook web app:** an optional facebook.com-only stylesheet tidies the feed, hides side
  rails on narrow windows and marks sponsored units, without touching other sites.
- **Screen saver:** choose the delay (1–60 min or off), style (drifting clock, APLite gradient or
  blurred wallpaper), drift on/off and fade duration in Settings → Security.
- **Task Manager:** a dock-button panel listing open windows with memory pressure and per-window
  close controls, plus minimize-all / close-all.
- **Window close animation:** windows fly back to their dock icon when closed.
- **Live configuration:** a small JSON manifest refreshes wallpaper palettes and an announcement
  without downloading or re-signing an IPA. Native code still requires a signed rebuild.
- **Performance mode:** lower-resolution frames, lighter shadows and no magnification for AirPlay
  or slow Wi-Fi.
- **Thermal monitor:** public iOS thermal-pressure API shown in the tray and quick panel, with
  battery level and colour-coded warnings (no private API, no °C claim).
- **Redrawn assets:** app icon, launch mark, lock mark and all built-in app icons regenerated in a
  single navy/teal glass style; the lock screen now uses one blur pass instead of two.
- **Animation system:** liquid-glass dock with hover magnification, open bounce, press feedback and
  stable insertion/removal transitions; spring window open/close/minimize/restore/snap; wallpaper
  fade, glass control centre, animated context menus and notifications, workspace sweep, press
  ripples and cursor-following glass reflection. All respect Reduce Motion (system or APLite switch).
- **Build/CI:** the unsigned artifact is named for what it is (`APLite-unsigned.ipa`) and is built
  from the `aplite-dev` branch.

Inherited from iDesk: window management, browser with tabs, Files, Spotlight, clipboard history,
screenshots, widgets, workspaces, iPhone trackpad/keyboard/mouse handling, the laptop-as-display
mode and the Guest Engine that runs decrypted IPA files in windows.

## Install

You need an iPhone or iPad on **iOS 17+** and a display (USB-C → HDMI/DisplayPort or an Apple
Lightning AV adapter). APLite is sideloaded:

1. Build or download an `APLite-unsigned.ipa`.
2. Sign it with your own certificate using ESign, Feather, Scarlet, SideStore or similar.
3. Install the signed app on the device. An **unsigned** IPA cannot be installed directly.
4. Open APLite, then connect the display.

To run iOS apps inside APLite, add **decrypted** IPA files on the Apps page and follow the
"Install new apps into APLite" step. App Store copies are encrypted and cannot run.

## Build

See [BUILD.md](BUILD.md). In short (macOS, Xcode 15+, XcodeGen):

```bash
brew install xcodegen
git clone -b aplite-dev https://github.com/oswi3525-glitch/APLITE.git
cd APLITE
xcodegen generate
scripts/build-ipa.sh            # → build/APLite.ipa (unsigned)
```

Or open `APLite.xcodeproj` and Run. The generated project and `build/` are ignored by Git.

## Development

- `-iDeskPreview` shows the desktop on the iPhone screen; `-iDeskInstall <ipa…>` and
  `-iDeskOpen <url>` are also supported. `scripts/sim-ipa.sh App.ipa` prepares an IPA for the
  Simulator.
- `python3 scripts/generate_assets.py` regenerates the bundled raster assets (needs Pillow).
- Layout: `App/` scenes, `Desktop/` desktop and browser, `Controller/` iPhone input, `Input/` mouse,
  `System/` APLite-owned modules (settings, security, power, memory, built-in web apps), `Guest/`
  IPA loading (Mach-O patching, lifecycle, UIKit shims, synthetic touches, crash reports).
- `python3 scripts/generate_meadow.py` and `python3 scripts/generate_ocean.py` regenerate the two
  bundled photo wallpapers locally; no network fetch is needed.
- The bundle identifier is intentionally kept as `com.hieuk.idesk` so signing, entitlements and the
  existing settings/guest-app storage keep working. Changing it requires a separate migration.

## About a mouse plugged into the TV

APLite does not support a mouse connected to the TV or monitor as an input device. A USB-C/HDMI
display connection carries video from the iPhone, and the TV's own USB port is controlled by the
TV's OS — neither delivers mouse HID events into APLite. Use the iPhone trackpad / a keyboard paired
to the iPhone, or *Use a laptop as the display*, where the laptop's own mouse and keyboard are sent
over Wi-Fi. The earlier draft mentioned TV USB mice; that claim has been removed.

## Known limitations

- Pages get synthetic mouse events, so CSS `:hover` does not always apply and some canvas pages
  ignore clicks (inherited from iDesk).
- Without an external display, only app management and the iPhone-side settings are available.
- Push notifications, iCloud, background tasks and extensions do not work for guest apps.
- No signed IPA is produced by CI unless you configure signing secrets and a provisioning profile.

## Documentation

[AUDIT_2026-11-22.md](AUDIT_2026-11-22.md) · [APLite_AUDIT.md](APLite_AUDIT.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [INDEPENDENCE.md](INDEPENDENCE.md) ·
[AUDIO_DIAGNOSTICS.md](AUDIO_DIAGNOSTICS.md) · [BUILD.md](BUILD.md) ·
[CHANGELOG.md](CHANGELOG.md) · [NOTICE.md](NOTICE.md) · [SYSTEM_TEST_PLAN.md](SYSTEM_TEST_PLAN.md)
