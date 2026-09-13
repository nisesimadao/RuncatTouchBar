#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install/open Xcode first." >&2
  exit 1
fi

rm -rf DerivedData dist RuncatTouchBar-test.zip

xcodebuild \
  -project RunCatNeo.xcodeproj \
  -scheme RunCatNeo \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p dist
cp -R DerivedData/Build/Products/Debug/RunCatNeo.app dist/RuncatTouchBar.app

# Ad-hoc sign so the locally built test app launches cleanly without a developer certificate.
codesign --force --deep --sign - dist/RuncatTouchBar.app

ditto -c -k --sequesterRsrc --keepParent dist/RuncatTouchBar.app RuncatTouchBar-test.zip

echo
echo "Built: $(pwd)/dist/RuncatTouchBar.app"
echo "ZIP:   $(pwd)/RuncatTouchBar-test.zip"
open -R dist/RuncatTouchBar.app
