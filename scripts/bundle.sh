#!/usr/bin/env bash
#
# bundle.sh — Assemble Galley.app from the SwiftPM release build (ADR-0017).
#
# SwiftPM does not emit a macOS .app bundle, so this script builds the `Galley`
# executable in release configuration and assembles a minimal, launchable
# application bundle around it: Contents/{Info.plist,MacOS/Galley,PkgInfo}. The
# script is the single, auditable bundle-assembly step on the swift build spine
# (ADR-0011); the `swift run` development path is unchanged.
#
# The on-disk .galley document format (prose.txt + sidecar.json, ADR-0007) is
# not touched here — this only produces the host application the OS can register
# and launch. Finder's single-file presentation of .galley is wired in Phase B2.
#
# Usage:   bash scripts/bundle.sh
# Output:  dist/Galley.app   (git-ignored)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PKG="$ROOT/app"
PLIST_SRC="$APP_PKG/Packaging/Info.plist"
DIST="$ROOT/dist"
APP="$DIST/Galley.app"
EXECUTABLE="Galley"

echo "==> Building $EXECUTABLE (release)..."
swift build -c release --package-path "$APP_PKG"
BIN_DIR="$(swift build -c release --package-path "$APP_PKG" --show-bin-path)"
BIN="$BIN_DIR/$EXECUTABLE"

if [[ ! -x "$BIN" ]]; then
	echo "error: built executable not found at $BIN" >&2
	exit 1
fi
if [[ ! -f "$PLIST_SRC" ]]; then
	echo "error: Info.plist template not found at $PLIST_SRC" >&2
	exit 1
fi

echo "==> Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc code signing makes Launch Services treat the bundle as a stable,
# registrable app (needed for the Phase B2 double-click flow) and avoids the
# "damaged or incomplete" Gatekeeper error on a freshly assembled bundle.
echo "==> Ad-hoc code signing..."
if ! codesign --force --sign - "$APP" >/dev/null 2>&1; then
	echo "warning: ad-hoc codesign failed; the app is unsigned but may still launch" >&2
fi

echo "==> Done: $APP"
