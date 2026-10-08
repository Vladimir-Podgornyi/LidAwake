#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 [--skip-notarize]" >&2
    echo "  NOTARY_PROFILE  notarytool keychain profile (default: lidawake-notary)" >&2
    echo "  ARCH            arm64 (default) or x86_64; x86_64 makes LidAwake-<version>-intel.dmg" >&2
}

SKIP_NOTARIZE=0
for ARG in "$@"; do
    case "$ARG" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $ARG" >&2; usage; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LidAwake"
ARCH="${ARCH:-arm64}"
case "$ARCH" in
    arm64)
        APP="build/$APP_NAME.app"
        DMG_SUFFIX=""
        ;;
    x86_64)
        APP="build/x86_64/$APP_NAME.app"
        DMG_SUFFIX="-intel"
        ;;
    *)
        echo "ERROR: unknown ARCH '$ARCH'. Use arm64 or x86_64." >&2
        exit 1
        ;;
esac
TEAM_ID="ZW984867UC"
NOTARY_PROFILE="${NOTARY_PROFILE:-lidawake-notary}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() {
    echo ""
    echo "==> $*"
}

notarize() {
    local FILE="$1"
    local RESULT="$WORK/notary-$(basename "$FILE").plist"
    local ID STATUS

    # A rejected submission can also end with a non-zero exit, so the status
    # is read from the result in both cases.
    xcrun notarytool submit "$FILE" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format plist > "$RESULT" || true

    ID="$(/usr/libexec/PlistBuddy -c "Print :id" "$RESULT" 2>/dev/null || true)"
    STATUS="$(/usr/libexec/PlistBuddy -c "Print :status" "$RESULT" 2>/dev/null || true)"
    echo "Submission $ID: $STATUS"

    if [[ "$STATUS" != "Accepted" ]]; then
        if [[ -n "$ID" ]]; then
            xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        else
            cat "$RESULT" >&2
        fi
        echo "ERROR: notarization of $FILE was not accepted (status: ${STATUS:-unknown})." >&2
        exit 1
    fi
}

step "Building $APP"
ARCH="$ARCH" ./scripts/build-app.sh

step "Checking the signature"
SIGN_INFO="$(codesign -dvv "$APP" 2>&1)"
AUTHORITY="$(sed -n 's/^Authority=//p' <<< "$SIGN_INFO" | head -n 1)"
SIGNED_TEAM="$(sed -n 's/^TeamIdentifier=//p' <<< "$SIGN_INFO")"
if [[ "$AUTHORITY" != "Developer ID Application: "* || "$SIGNED_TEAM" != "$TEAM_ID" ]]; then
    echo "ERROR: $APP is not signed with a Developer ID Application certificate of team $TEAM_ID." >&2
    echo "ERROR: Signer: ${AUTHORITY:-none (ad-hoc)}. A release needs a Developer ID signature." >&2
    exit 1
fi
echo "Signed by $AUTHORITY"

# Sign the disk image with exactly the certificate that signed the app.
codesign -d --extract-certificates="$WORK/cert" "$APP" 2>/dev/null
IDENTITY="$(openssl x509 -inform DER -in "$WORK/cert0" -noout -fingerprint -sha1 \
    | sed 's/^.*=//; s/://g')"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="build/$APP_NAME-$VERSION$DMG_SUFFIX.dmg"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    step "Notarizing $APP (profile $NOTARY_PROFILE)"
    ditto -c -k --keepParent "$APP" "$WORK/$APP_NAME.zip"
    notarize "$WORK/$APP_NAME.zip"
    xcrun stapler staple "$APP"
else
    step "Skipping notarization of $APP"
fi

step "Creating $DMG"
STAGING="$WORK/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    "$DMG"

step "Signing $DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    step "Notarizing $DMG (profile $NOTARY_PROFILE)"
    notarize "$DMG"
    xcrun stapler staple "$DMG"

    step "Verifying"
    xcrun stapler validate "$APP"
    xcrun stapler validate "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
    step "Skipping notarization of $DMG, stapler and spctl checks"
fi

step "Done"
echo "DMG:     $ROOT/$DMG"
SIZE="$(stat -f %z "$DMG")"
echo "Size:    $SIZE bytes ($(awk -v s="$SIZE" 'BEGIN { printf "%.1f MiB", s / 1048576 }'))"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d ' ' -f 1)"
