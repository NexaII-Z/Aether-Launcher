#!/usr/bin/env bash
# Builds an unsigned AETHERLauncher.ipa. Run from anywhere; needs macOS, Xcode and XcodeGen.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="AETHERLauncher"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
IPA_NAME="$SCHEME-unsigned.ipa"
LOG="$BUILD_DIR/xcodebuild.log"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [ ! -d "$SCHEME.xcodeproj" ]; then
  echo "Generating Xcode project with XcodeGen..."
  xcodegen generate --spec project.yml
fi

echo "Archiving $SCHEME (Release, iphoneos, unsigned)..."
set +e
xcodebuild archive \
  -project "$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  echo "xcodebuild failed with exit code $STATUS. Errors:"
  grep -E "error:" "$LOG" | sort -u | while read -r line; do echo "::error::$line"; done || true
  exit "$STATUS"
fi

APP_PATH="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP_PATH" ]; then
  echo "::error::No .app found inside the archive at $ARCHIVE/Products/Applications"
  exit 1
fi

echo "Packaging $APP_PATH into an IPA..."
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
(cd "$BUILD_DIR" && zip -qry "$IPA_NAME" Payload && rm -rf Payload)

echo "Done: $BUILD_DIR/$IPA_NAME ($(du -h "$BUILD_DIR/$IPA_NAME" | cut -f1))"
