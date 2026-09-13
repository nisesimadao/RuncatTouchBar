#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install/open Xcode first." >&2
  exit 1
fi

pkill -x RunCatNeo >/dev/null 2>&1 || true
pkill -x RuncatTouchBar >/dev/null 2>&1 || true

rm -rf DerivedData dist RuncatTouchBar-test.zip

xcodebuild \
  -project RunCatNeo.xcodeproj \
  -scheme RunCatNeo \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

mkdir -p dist
cp -R DerivedData/Build/Products/Debug/RunCatNeo.app dist/RuncatTouchBar.app

codesign --force --deep --sign - dist/RuncatTouchBar.app

ditto -c -k --sequesterRsrc --keepParent dist/RuncatTouchBar.app RuncatTouchBar-test.zip

echo
echo "Built: $(pwd)/dist/RuncatTouchBar.app"
echo "ZIP:   $(pwd)/RuncatTouchBar-test.zip"

open -n dist/RuncatTouchBar.app
sleep 2

if pgrep -x RunCatNeo >/dev/null 2>&1 || pgrep -x RuncatTouchBar >/dev/null 2>&1; then
  echo "Launched successfully. Check the Touch Bar Control Strip for RunCat."
else
  echo "Build succeeded, but the app process was not detected after launch." >&2
  exit 2
fi
