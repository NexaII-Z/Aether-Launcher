#!/usr/bin/env bash
# Re-signs an IPA with YOUR certificate and provisioning profile. Needs macOS (codesign, security).
# Usage: sign_ipa.sh <in.ipa> <out.ipa> [bundle-id-for-wildcard-profiles]
# Env:   P12_BASE64, P12_PASSWORD, PROVISION_BASE64
set -euo pipefail
IN="$1"; OUT="$2"; WANT_BUNDLE="${3:-com.aether.minecraftpe}"
: "${P12_BASE64:?Set the P12_BASE64 secret}" "${P12_PASSWORD:?Set the P12_PASSWORD secret}" "${PROVISION_BASE64:?Set the PROVISION_BASE64 secret}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"; security delete-keychain "$KC" 2>/dev/null || true' EXIT
KC="$WORK/aether.keychain-db"; KCPW="$(uuidgen)"
mkdir -p "$WORK/ipa"; unzip -q "$IN" -d "$WORK/ipa"
APP="$(find "$WORK/ipa/Payload" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "::error::No .app inside $IN"; exit 1; }

echo "$P12_BASE64" | base64 --decode > "$WORK/cert.p12"
echo "$PROVISION_BASE64" | base64 --decode > "$WORK/profile.mobileprovision"
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KCPW" "$KC"
security import "$WORK/cert.p12" -k "$KC" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KCPW" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
IDENTITY="$(security find-identity -v -p codesigning "$KC" | awk '/[0-9A-F]{40}/{print $2; exit}')"
[ -n "$IDENTITY" ] || { echo "::error::No valid code-signing identity in the .p12 (wrong password, expired or revoked?)"; exit 1; }

security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist"
APPID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$WORK/profile.plist")"
PROFILE_BUNDLE="${APPID#*.}"
if [[ "$PROFILE_BUNDLE" == *"*" ]]; then
  NEW_BUNDLE="$WANT_BUNDLE"
  case "$NEW_BUNDLE" in ${PROFILE_BUNDLE}) ;; *) echo "::error::Bundle id $NEW_BUNDLE does not match the wildcard profile $PROFILE_BUNDLE"; exit 1;; esac
else
  NEW_BUNDLE="$PROFILE_BUNDLE"
fi
echo "Signing as bundle id $NEW_BUNDLE with $(/usr/libexec/PlistBuddy -c 'Print :Name' "$WORK/profile.plist")"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$WORK/profile.plist" > "$WORK/entitlements.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $NEW_BUNDLE" "$APP/Info.plist"
cp "$WORK/profile.mobileprovision" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

# Inside-out: nested code first, then the app.
find "$APP" -type d \( -name '*.framework' -o -name '*.appex' \) -prune -print0 | while IFS= read -r -d '' item; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$item"
done
find "$APP" -name '*.dylib' -print0 | while IFS= read -r -d '' lib; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$lib"
done
codesign --force --sign "$IDENTITY" --entitlements "$WORK/entitlements.plist" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && echo "codesign verify: OK"

mkdir -p "$(dirname "$OUT")"; OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"; rm -f "$OUT_ABS"
(cd "$WORK/ipa" && zip -qry "$OUT_ABS" Payload)
echo "Signed IPA: $OUT"
