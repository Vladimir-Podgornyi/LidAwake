#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="LidAwake"
APP="build/$APP_NAME.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "Built $APP"
