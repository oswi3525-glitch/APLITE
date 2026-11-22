#!/bin/bash
# Build an unsigned iDesk.ipa (Release, device) for signing with ESign, Feather, Scarlet, …
# Usage: scripts/build-ipa.sh            → build/iDesk.ipa
# Optional: VERSION=1.2.0 BUILD_NUMBER=42 scripts/build-ipa.sh   (otherwise the values in project.yml)
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null; then
  xcodegen -q
elif [ ! -d iDesk.xcodeproj ]; then
  echo "XcodeGen is needed to create the project: brew install xcodegen" >&2
  exit 1
fi

APP=build/DerivedData/Build/Products/Release-iphoneos/iDesk.app
mkdir -p build
rm -rf "$APP"   # so a failed build can never ship an older app

SETTINGS=(CODE_SIGNING_ALLOWED=NO)
[ -n "${VERSION:-}" ] && SETTINGS+=("MARKETING_VERSION=$VERSION")
[ -n "${BUILD_NUMBER:-}" ] && SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")

set +e
xcodebuild -project iDesk.xcodeproj -scheme iDesk -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData "${SETTINGS[@]}" build > build/xcodebuild.log 2>&1
STATUS=$?
set -e
grep -E "error:|warning: |BUILD (SUCCEEDED|FAILED)" build/xcodebuild.log | grep -v "appintentsmetadataprocessor" || true
if [ $STATUS -ne 0 ] || [ ! -d "$APP" ]; then
  echo "Build failed (full log: build/xcodebuild.log)" >&2
  exit 1
fi

rm -rf build/ipa && mkdir -p build/ipa/Payload && cp -R "$APP" build/ipa/Payload/
(cd build/ipa && rm -f ../iDesk.ipa && zip -qry ../iDesk.ipa Payload)
rm -rf build/ipa
echo "→ build/iDesk.ipa"
