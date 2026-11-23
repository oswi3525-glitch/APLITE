# APLite system expansion — verification plan

This repository is prepared on Linux without Xcode. Compilation, unit tests and IPA packaging happen
**only** on the macOS GitHub Actions runner. The checklists below are what must be done on a real
iPhone/iPad before any item is marked complete. Status today: **not tested on hardware**.

## Automated (CI, `Build APLite` workflow)

- [ ] `xcodegen generate` succeeds with the new `APLiteTests` target.
- [ ] `xcodebuild test -scheme APLiteTests` passes: audio diagnostics, security backoff, memory
      heuristics, certificate rules, file sorting, window layout, project analysis.
- [ ] `scripts/build-ipa.sh` produces `APLite-unsigned.ipa` and it is uploaded as an artifact.
- [ ] The IPA contains `APLite/System/*.swift` compiled into the app (symbol check in the build log).

## Security

- [ ] Set a 4+ character passcode; confirm it is required after launch when "Lock when APLite opens" is on.
- [ ] Change the passcode with the old one; verify the old one stops working.
- [ ] Wrong passcode 3/5/8/10 times: delays of 30 s / 2 min / 10 min / 1 h appear and survive restart.
- [ ] Face ID / Touch ID path still works when no APLite passcode is set.
- [ ] Sleep locks the desktop; Wake asks for authentication when configured.
- [ ] Confirm the passcode/hash never appears in Xcode console, `os_log`, crash reports or Settings.

## Power

- [ ] Sleep suspends guest apps; Wake resumes them without relaunching the IPA.
- [ ] Shutdown closes all windows and guest apps stop audio/animation.
- [ ] APLite reports state "Shut down"; Restart restores the saved session when enabled.
- [ ] Confirm UI text makes clear this does not power off the iPhone/iPad.

## Memory

- [ ] Task Manager shows live RAM and peak; peak never decreases during one session.
- [ ] RAM approaches the 1 GB target: warning toast appears; background tabs are discarded.
- [ ] "Release caches now" reduces footprint; Quick Look image cache is dropped.
- [ ] A sustained-growth scenario shows "possible leak" as a hint, then verify manually (no false claim).

## Certificates

- [ ] Import `.p12` and `.pfx` from Files with the correct password: identity and Team ID shown.
- [ ] Wrong password → specific message; truncated/random file → damaged message; certificate without
      private key → specific message; wrong extension → unsupported message.
- [ ] Password/private key never printed in logs.
- [ ] Signing a guest app with an imported certificate still works (Guest Engine unchanged).

## Files

- [ ] Folder rows show recursive total size; metadata shows kind, size and date.
- [ ] Sorting by name/date/size works in both directions and puts folders first.
- [ ] "APLite system files" writes a diagnostics report into Application Support/APLite and opens it.
- [ ] Multiple Files windows keep independent folders; drag and drop still works.
- [ ] No access to another app's sandbox is attempted (review by code and by entitlements).

## Windows

- [ ] Tile arranges windows without overlap; minimize/maximize/snap/restore still work afterwards.
- [ ] Close every window while Alt+Tab / Recent Apps is open: no crash.
- [ ] Restoring a saved layout after a display resolution change clamps windows on screen.

## Settings & Build Center

- [ ] All ten groups appear; every toggle changes real state and survives an app restart.
- [ ] Build Center analysis reports correct Swift file count, Bundle ID, dependencies and warnings.
- [ ] With no worker configured, requesting a build reports "not configured" — it never fakes success.
- [ ] With a real GitHub token, a dispatch request is accepted (HTTP 204) and run statuses come from
      the API; IPA download is offered only for runs whose API conclusion is `success`.

## App Creator

- [ ] Generate each of the three templates; open the ZIP and confirm real Swift + project.yml files.
- [ ] Bundle ID and display name with spaces/quotes produce a valid module name and source.
- [ ] "Analyse in Build Center" reads the generated project and reports the correct Bundle ID.
- [ ] A build request sent to a real macOS worker compiles the generated project (only then claim it builds).

## Accounts (1.2.6)

- [ ] Sign in to Facebook / Zalo / Gmail in a window on the **external display** with the iPhone
      already backgrounded; the account appears in desktop Settings → Accounts & cookies within a
      couple of seconds without pressing any save button.
- [ ] Disconnect the display and shut APLite down: re-launch restores the signed-in session.
- [ ] Re-saving the same account shows a success count (not "no cookies found") and the vault file
      keeps `HttpOnly` / `SameSite` values after a round-trip.
- [ ] "Clear" removes cookies from WebKit and "Forget" removes them from the vault; a cleared domain
      is not silently restored at the next launch.

## On-screen keyboard (1.2.6)

- [ ] Enable it in native Settings → Input (and in desktop Settings → Typing); it stays hidden until
      an input field is clicked in a web page, the address bar, the find bar, a sticky note, Files or
      the editor.
- [ ] Every key works in a web input and in the text editor: letters (uppercase after Shift, Caps
      Lock persists), digits/symbols via 123, Backspace, Enter, Tab, arrows, Home/End, PgUp/PgDn,
      Delete, Esc, Select all / Copy / Paste, and Space.
- [ ] × hides the keyboard with the slide-down animation; clicking another field brings it back;
      Esc also hides it. "Keep it visible" shows it even with no field focused.
- [ ] Keyboard sizing and click feedback (iPhone haptic) work, and the full keyboard settings page
      lists every supported key.
- [ ] The hardware/iPhone keyboard and Voice Typing still type into the same field while the virtual
      keyboard is shown.

## Tabs & Facebook (1.2.6)

- [ ] Find bar closes when switching or closing tabs; match counts always belong to the shown page.
- [ ] ⌘⇧T restores a closed tab at its original position, including after "Close other tabs".
- [ ] Multiple Facebook/Zalo windows show the branded icon and app name in the dock and switcher.
- [ ] Tab strip stays readable with many tabs; favicons appear where available.
- [ ] Clean Facebook toggle changes the layout immediately and survives navigation and relaunch;
      other sites are untouched.

## 1.2.7 — system overhaul

- [ ] Open Gmail at `mail.google.com`: no "browser version is no longer supported" banner; sign-in and a Google OAuth popup still work.
- [ ] Google Search, YouTube, GitHub and a modern JS-framework site load and respond to synthetic clicks.
- [ ] Verify no site is told APLite is Chrome/Chromium; the UA contains `Version/<iOS> Safari/605.1.15` only.
- [ ] Force a WebContent termination (memory pressure): the tab reloads once, then stops retrying if it keeps crashing.
- [ ] Pure red status indicators (recording dot, errors, tray warning, danger buttons) look red, not pink, in dark dock, light dock and with the night filter on.
- [ ] Drag a WebApp icon onto the Trash: the icon highlights, the app disappears from desktop/Launcher/dock, and its pin/recents/slot are cleaned.
- [ ] Drag an imported guest app to the Trash after closing its window: it is removed; a bundled app is only marked and the toast explains the re-sign/reinstall step.
- [ ] Native iOS apps are never offered for uninstall; system pages (Browser/Files/Settings/Trash) reject the drop.
- [ ] Zoom a WebApp through ⌘+/⌘−/⌘0 and the menu: 9 levels, page reflows, scroll still works, clicks land correctly, other WebApps are unchanged, and the level survives restart.
- [ ] No user-visible iDesk branding remains; LICENSE/NOTICE/About attribution is intact.

## Known unresolved issues

Record any failures here before merging to `main`. Do not mark a feature complete on the strength of
a successful compile alone.
