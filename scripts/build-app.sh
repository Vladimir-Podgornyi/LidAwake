#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LidAwake"
HELPER_NAME="LidAwakeHelper"
HELPER_ID="com.vladimirpodgornyi.LidAwake.helper"
APP="build/$APP_NAME.app"
HELPER="$APP/Contents/MacOS/$HELPER_NAME"

# The Swift driver links via clang with --sysroot, from which clang does not
# read the SDK version, so LC_BUILD_VERSION would record the deployment target
# as the SDK. Passing -isysroot to the linking clang records the real SDK.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
swift build -c release \
    -Xswiftc -Xclang-linker -Xswiftc -isysroot \
    -Xswiftc -Xclang-linker -Xswiftc "$SDK_PATH"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$HELPER_NAME" "$HELPER"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "Resources/$HELPER_ID.plist" "$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist"

# actool can exit with 0 after an error, so the outputs are checked below.
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
mkdir -p "$APP/Contents/Resources"
xcrun actool Resources/AppIcon.icon \
    --compile "$APP/Contents/Resources" \
    --app-icon AppIcon \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 13.0 \
    --output-partial-info-plist "$ICON_TMP/partial.plist" \
    --output-format human-readable-text --errors --warnings --notices
for ICON_FILE in Assets.car AppIcon.icns; do
    if [[ ! -f "$APP/Contents/Resources/$ICON_FILE" ]]; then
        echo "ERROR: actool did not produce $ICON_FILE from Resources/AppIcon.icon." >&2
        exit 1
    fi
done

TEAM_ID="ZW984867UC"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    IDENTITY="$SIGN_IDENTITY"
else
    IDENTITY="$(security find-identity -v -p codesigning \
        | grep -F "Developer ID Application" \
        | grep -F "($TEAM_ID)" \
        | head -n 1 \
        | awk '{print $2}' || true)"
fi

if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
    codesign --force --sign - --identifier "$HELPER_ID" "$HELPER"
    codesign --force --sign - "$APP"
    echo "" >&2
    echo "WARNING: ad-hoc signature. No Developer ID Application certificate for team $TEAM_ID was used." >&2
    echo "WARNING: The privileged helper will not work in this build." >&2
    echo "" >&2
else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp --identifier "$HELPER_ID" "$HELPER"
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"

    # Read the requirements back from the binaries, so the check uses exactly
    # what the app and the helper enforce at run time.
    APP_REQ="$(strings "$HELPER" | grep -m 1 -F "identifier \"com.vladimirpodgornyi.LidAwake\" " || true)"
    HELPER_REQ="$(strings "$APP/Contents/MacOS/$APP_NAME" | grep -m 1 -F "identifier \"$HELPER_ID\" " || true)"
    if [[ -z "$APP_REQ" || -z "$HELPER_REQ" ]]; then
        echo "ERROR: code signing requirements not found in the binaries." >&2
        exit 1
    fi
    codesign --verify --strict -R="$HELPER_REQ" "$HELPER"
    codesign --verify --strict -R="$APP_REQ" "$APP"
    echo "Signatures satisfy the app and helper requirements"
fi

codesign --verify --strict "$HELPER"
codesign --verify --strict "$APP"

echo "Built $APP"
