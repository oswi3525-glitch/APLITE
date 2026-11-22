#!/bin/bash
# Convert a decrypted device IPA so it can be loaded by APLite in the iOS Simulator (Apple silicon Macs).
# The arm64 code is the same; only the platform in each Mach-O is changed, then everything is ad-hoc signed.
# Usage: scripts/sim-ipa.sh App.ipa      → App-sim.ipa next to it
set -euo pipefail
IPA="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="${IPA%.ipa}-sim.ipa"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
unzip -q "$IPA"
APP=$(ls -d Payload/*.app)
rm -rf "$APP/PlugIns" "$APP/Extensions" "$APP/Watch" "$APP/AppClips" "$APP/_CodeSignature"
find "$APP" -type f | while IFS= read -r f; do
  if file "$f" | grep -q "Mach-O"; then
    vtool -set-build-version iossim 17.0 17.0 -replace -output "$f.tmp" "$f" >/dev/null 2>&1 && mv "$f.tmp" "$f"
  fi
done
find "$APP/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -exec codesign -f -s - {} \; 2>/dev/null || true
codesign -f -s - "$APP" >/dev/null 2>&1 || codesign -f -s - "$APP/$(plutil -extract CFBundleExecutable raw "$APP/Info.plist")"
rm -f "$OUT" && zip -qry "$OUT" Payload
echo "→ $OUT"
