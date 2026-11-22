# iDesk

**Desktop mode for iPhone and iPad.** Plug it into a monitor or TV (or mirror to an Apple TV over AirPlay): the big
screen gets a desktop with windows, a taskbar, an app menu, desktop websites and iOS apps in windows. The iPhone or
iPad becomes the trackpad and keyboard.

[Tiếng Việt](README.vi.md)

> **Experimental.** iDesk uses private UIKit APIs, is meant to be sideloaded, and a future iOS may break parts of it.

## Features

- **Spotlight** (⌘ + Space or the magnifier on the taskbar): apps, open windows, files, bookmarks and history in one
  search, plus sums (`(12+3)*4`, `15% of 80`) and unit conversions (`5 km to mi`, `100 f to c`).
- **App windows** you move, resize, minimize and maximize. Drag one to the top edge to pick a layout (halves, thirds,
  quarters); once a window takes one side, iDesk offers the other windows for the rest. ⌘ + arrows snap too. Keep a
  window on top from its title bar menu. A taskbar with Recent apps, Home and Back; an app menu with search and a
  Recent row; ⌥ + Tab, ⌘ + Q / H / `; workspaces and hot corners (optional). Open windows come back next time.
- **Clipboard history** (⌘ + Shift + V): what you copied on the desktop, pinned items first.
- **Screenshots** of the whole screen (⌘ + Shift + 3) or of an area or a window (⌘ + Shift + 4), saved to Photos and
  Files, copied, and shown in the corner. **Sticky notes** on the desktop (right-click the desktop).
- **Browser** with tabs, desktop sites, sign-in popups, fullscreen video, find in page, zoom, a bookmarks bar and history,
  ad and tracker blocking with your own block and allow lists, a volume slider that works on web videos, a text size for every page, dark pages, translate, reader view and read aloud. Install a
  site as an app (its own window and icon), pop a video out into a small floating player, move a tab to a window
  beside, and present slides or a PDF with the iPhone as the remote and laser pointer.
- **Downloads** panel on the taskbar: progress, pause, resume, cancel. Drag a file from Files onto a web page to
  upload it.
- **Screen recording** of the desktop (⌘ + Shift + 5) to Photos and Files.
- **Files**: downloads and screenshots, folders, rename, move, search (names and text inside files), sort, new text
  file, zip and unzip, a Trash to put files back from, import from the iPhone, Quick Look (Space). Text files open in an editor with autosave, find and replace, and Save as.
- **iOS apps from decrypted IPA files**, running in windows, several at once. They reopen next time, unless iDesk
  quit unexpectedly: the Apps page then marks the app that was in use.
- **The iPhone as input**: trackpad gestures, typing in any language (Telex, VNI…), voice typing, a Bluetooth
  keyboard (volume and play/pause keys too), a mouse through AssistiveTouch, a game controller, emoji (⌃⌘Space), text
  replacement, and a paste button for what you copied on the iPhone (a password, say).
- **Desktop**: icons you arrange and size, files on the desktop, wallpapers (one per workspace, or one that follows
  the time of day), widgets you drag anywhere (clock, month, weather, events, reminders, focus timer), a night filter,
  shake the pointer to find it, a lock with Face ID and a screen saver, quick panel and notifications, battery, heat
  and memory in the tray, display resolution and TV overscan.
- **A laptop as the display**: no cable needed. iDesk shows the desktop in the laptop's browser over Wi-Fi, and the
  laptop's mouse and keyboard (with its input methods, Vietnamese included) control it. Macs can also take the desktop
  over AirPlay.
- **Check setup** on the iPhone: the display, keyboard, mouse, free space and apps, each with a plain fix. The Apps
  page lists apps others got working (compat.json, grows with reports) and has a **Report** button per app.
- **TV mode** in one click (720p, larger text and icons); tabs nobody is looking at are set aside when memory runs low;
  leftovers of interrupted installs and updates are removed, and the apps' caches can be cleared.
- Update checks on GitHub Releases: **Update** downloads the new iDesk and puts your iOS apps into it, so one
  signing with ESign updates iDesk and keeps the apps.
- A first-run guide, crash and freeze reports with a **Copy error** button, English and Vietnamese.

## Install

You need an iPhone on **iOS 17+** and a USB-C → HDMI/DisplayPort cable (or Apple's Lightning AV adapter).

Download `iDesk-<version>.ipa` from [Releases](https://github.com/itshieuk/iDesk/releases), then sign and install it
with ESign, Feather or Scarlet. To build it yourself (Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
brew install xcodegen
git clone https://github.com/itshieuk/iDesk.git && cd iDesk
xcodegen
scripts/build-ipa.sh      # → build/iDesk.ipa (or open iDesk.xcodeproj and Run)
```

## Using iDesk

Open iDesk, then connect the display.

| On the iPhone           | Does                          | Keyboard (⌘ or Ctrl)  | Does                            |
| ----------------------- | ----------------------------- | --------------------- | ------------------------------- |
| One finger              | Move the pointer              | T / N / W             | New tab / window, close         |
| Tap / two-finger tap    | Click / right-click           | Shift + T             | Reopen what you closed          |
| Two-finger drag         | Scroll                        | L / R                 | Address bar / reload            |
| Hold, then drag         | Move or resize a window       | F / G                 | Find / next match               |
| Three fingers ↑ / ↓ / • | Recent apps / Home / Back     | = / − / 0             | Zoom                            |
| Four-finger tap         | App menu                      | ⌘ alone / Tab         | App menu, Recent apps           |
| Turn it sideways        | The whole screen is the pad   | /                     | Every shortcut                  |

On a keyboard without ⌘, the logo key does the same. A mouse works through *Settings → Accessibility → Touch → AssistiveTouch*: the iPhone
then shows a copy of the desktop to point at (the **Mouse check** shows what reaches iDesk). Settings are on the
desktop; with no display, the gear on the iPhone keeps the trackpad and mouse settings.

## iOS apps from IPA files

1. Tap **Apps** (the box button) on the iPhone and add decrypted `.ipa` files.
2. Tap **Install new apps into iDesk** and pick ESign: it signs iDesk again with the apps inside and installs it.
3. Open iDesk again: the apps are in the app menu.

iOS only runs code that ships inside an installed app, hence the reinstall (with a development certificate, the
**Advanced** section signs apps on the iPhone instead). Apps installed from the App Store can't be shown: iOS keeps
every app in its own sandbox.

Most apps work: screens, touches, typing, network, sign-in, saved data. Push notifications, iCloud, background tasks
and extensions don't. Apps that check for tampering may quit, and all apps share iDesk's memory. If one crashes
iDesk, the next launch shows **Copy error**: please send that text.

## Development

- `-iDeskPreview` shows the desktop on the iPhone screen (touch it; hold for a right-click). Add
  `-iDeskInstall <ipa…>` or `-iDeskOpen <url>`. `scripts/sim-ipa.sh App.ipa` makes an IPA run in the Simulator.
- Code: `App/` scenes, `Desktop/` the desktop and browser, `Controller/` the iPhone screen, `Input/` mouse,
  `Guest/` loading apps (Mach-O patching, lifecycle, shims for bundle, keychain and process-wide hooks, synthetic
  touches, crash reports).
- Texts: `iDesk/Localizable.xcstrings`. Releases: push a tag such as `v0.5.2`.

**Known issues:** pages get mouse events from JavaScript, so CSS `:hover` doesn't apply and some canvas pages
ignore clicks. Without a display, only app management works.

[MIT](LICENSE) · Only load apps you have the right to use. iDesk is not affiliated with Apple or any app developer.
