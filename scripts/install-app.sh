#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="build/LidAwake.app"
TARGET="/Applications/LidAwake.app"

if [[ ! -d "$SOURCE" ]]; then
    echo "ERROR: $SOURCE not found. Run scripts/build-app.sh first." >&2
    exit 1
fi

if pgrep -x LidAwake >/dev/null; then
    pkill -x LidAwake || true
    for _ in {1..50}; do
        pgrep -x LidAwake >/dev/null || break
        sleep 0.1
    done
    if pgrep -x LidAwake >/dev/null; then
        echo "ERROR: LidAwake is still running." >&2
        exit 1
    fi
fi

rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"

echo "Installed $TARGET"
