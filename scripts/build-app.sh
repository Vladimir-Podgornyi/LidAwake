#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LidAwake"
APP="build/$APP_NAME.app"

# The Swift driver links via clang with --sysroot, from which clang does not
# read the SDK version, so LC_BUILD_VERSION would record the deployment target
# as the SDK. Passing -isysroot to the linking clang records the real SDK.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
swift build -c release \
    -Xswiftc -Xclang-linker -Xswiftc -isysroot \
    -Xswiftc -Xclang-linker -Xswiftc "$SDK_PATH"
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

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
    codesign --force --sign - "$APP"
    echo "" >&2
    echo "WARNING: ad-hoc signature. No Developer ID Application certificate for team $TEAM_ID was used." >&2
    echo "WARNING: The privileged helper will not work in this build." >&2
    echo "" >&2
else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
fi

codesign --verify --strict "$APP"

echo "Built $APP"
