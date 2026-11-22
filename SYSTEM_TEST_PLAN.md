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

## Known unresolved issues

Record any failures here before merging to `main`. Do not mark a feature complete on the strength of
a successful compile alone.
