# Building APLite

## Requirements

- macOS 15 with Xcode 16 (the project targets iOS 17+, iPhone and iPad).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- No Swift Package dependencies, submodules or Git LFS objects.

## Project facts (verified from `project.yml`)

| Item | Value |
| --- | --- |
| Project / scheme / target | `APLite.xcodeproj` / `APLite` / `APLite` (unit tests: `APLiteTests`) |
| Source folder | `APLite/` (renamed from `iDesk/`; guest identifiers and persistence keys are intentionally unchanged) |
| Bundle identifier | `com.hieuk.idesk` (deliberately unchanged — see below) |
| Deployment target | iOS 17.0 |
| Device family | 1,2 (iPhone and iPad) |
| Signing | Automatic in Xcode; CI builds **unsigned** |
| Frameworks | UIKit, SwiftUI, WebKit, PhotosUI, UniformTypeIdentifiers, GameController, QuartzCore |
| Info.plist | `APLite/Info.plist` |
| Live config | `aplite-live.json` (data only; native code still needs a signed IPA) |
| Bridging header | `APLite/APLite-Bridging-Header.h` |

The bundle identifier is intentionally the upstream one. Changing it would break existing signed
installations, guest-app storage and any App Group/entitlement configuration. APLite preserves
user data when installed over iDesk. If you need a distinct identity, change it in a dedicated
migration commit together with a UserDefaults/GuestApps migration.

## Local build

```bash
git clone -b aplite-dev https://github.com/oswi3525-glitch/APLITE.git
cd APLITE
xcodegen generate
xcodebuild -project APLite.xcodeproj -scheme APLite -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

The supported one-liner is:

```bash
scripts/build-ipa.sh     # → build/APLite.ipa (unsigned)
```

Optional environment variables: `VERSION=1.0.0 BUILD_NUMBER=42 scripts/build-ipa.sh`.
A failed build removes the stale `.app` first, so `build/APLite.ipa` can never be from an older
commit. The complete compiler output is in `build/xcodebuild.log`.

## Signing

CI and `build-ipa.sh` produce **unsigned** IPAs. An unsigned IPA cannot be installed on an iPhone.
Sign it with your own certificate using ESign / Feather / Scarlet / SideStore, or use Xcode with a
development team for on-device runs.

No certificate, provisioning profile, password or private key is stored in this repository, and
the CI workflow does not claim to sign. To add signed builds later:

1. Store the base64 `.p12`, its password and the provisioning profile as GitHub Actions Secrets.
2. Import them into a temporary keychain in a separate workflow job.
3. Use `xcodebuild -exportArchive` with an export options plist generated at runtime.
4. Name the result `APLite-signed.ipa`. Never rename an unsigned build as signed.

## GitHub Actions

`.github/workflows/build.yml` runs on every push to `aplite-dev` or a `fix/*` branch, and on `workflow_dispatch`:

1. Checkout, select Xcode, install XcodeGen.
2. Resolve Swift Package dependencies if any are declared (currently none).
3. `scripts/build-ipa.sh` → `build/APLite.ipa`.
4. Run `xcodebuild test` for the `APLiteTests` target on an available iPhone Simulator
   (currently the audio-diagnostics unit tests).
5. Rename to `APLite-unsigned.ipa` and upload as an artifact.
6. Upload the build and test logs on failure and print a build summary.

`.github/workflows/release.yml` builds `APLite-unsigned-<version>.ipa` when a `v*` tag is pushed
or the workflow is dispatched manually. No release is created automatically by development pushes.

## Regenerating assets

Bundled images are committed, so normal builds do not need Python. To redesign them:

```bash
python3 -m pip install pillow
python3 scripts/generate_assets.py
```

The script writes `APLite/Assets.xcassets/` deterministically (app icon, launch mark, launch
background, accent colour and the four built-in app icons).

## Audio diagnostics

Audio from guest apps, web pages, Quick Look and speech shares one `AVAudioSession`. It is now owned
by `App/AudioSessionManager.swift`. See [AUDIO_DIAGNOSTICS.md](AUDIO_DIAGNOSTICS.md) for the root
cause analysis, the repair, the on-device test checklist and how to export a diagnostics report
(Settings → Sound → Copy audio diagnostics, or `-iDeskScript "audio"` in a Debug build).

## Testing status

Compilation, IPA packaging and the `APLiteTests` unit tests are performed by the macOS GitHub
Actions runner. The Linux development container used to prepare APLite has no Xcode, Swift compiler
or UIKit, so no local build, simulator run or on-device test is claimed here. CI outcomes are reported
in the workflow summary and linked from [CHANGELOG.md](CHANGELOG.md); audio behaviour on real
hardware is listed as unverified until the checklist in AUDIO_DIAGNOSTICS.md is completed.

## Live configuration

`aplite-live.json` at the repository root is fetched at launch by `LiveUpdate.swift`. It can
refresh wallpaper palettes and a short announcement without rebuilding or re-signing. It contains
**data, never executable code**. iOS forbids swapping native code inside a running app; real code
updates still come through `UpdateChecker` as a signed IPA and must be signed by you.
