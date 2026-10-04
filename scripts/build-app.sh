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

codesign --force --sign - "$APP"

echo "Built $APP"
