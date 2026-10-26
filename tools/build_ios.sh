#!/usr/bin/env bash
# Build The Devouring for iOS.
#
#   tools/build_ios.sh export     # Godot -> Xcode project only
#   tools/build_ios.sh archive    # export + unsigned release archive  (default)
#   tools/build_ios.sh ipa        # archive + signed .ipa   (needs an Apple ID in Xcode)
#   tools/build_ios.sh upload     # archive + upload to App Store Connect
#
# Output goes to a SIBLING directory, not inside the project. Godot resolves an export path that
# lives under the project as a `res://` path and then tries to re-read its own output as a game
# resource, which produces a wall of "Can't open file from path 'res://build/...'" errors.

set -euo pipefail

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(dirname "$PROJECT_DIR")/TheDevouring-build/ios"
PRESET="iOS"
SCHEME="TheDevouring"
TEAM_ID="${TEAM_ID:-}"   # your Apple Developer Team ID

MODE="${1:-archive}"

say() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

[ -x "$GODOT" ] || { echo "Godot not found at $GODOT — set GODOT=/path/to/Godot" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
say "Exporting Xcode project"
mkdir -p "$BUILD_DIR"
cd "$PROJECT_DIR"

# Reimport first: regenerated art (tools/gen_art.py, tools/gen_icon.py) is otherwise served from a
# stale import cache and the build silently ships the previous sprites.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

"$GODOT" --headless --path . --export-release "$PRESET" "$BUILD_DIR/$SCHEME.xcodeproj" 2>&1 \
	| grep -vE "Can't open file from path 'res://" \
	| grep -iE "ERROR|error:|DONE" || true

[ -d "$BUILD_DIR/$SCHEME.xcodeproj" ] || { echo "Export produced no Xcode project." >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
say "Patching Info.plist"
PLIST="$BUILD_DIR/$SCHEME/$SCHEME-Info.plist"

# Godot's template writes NSCameraUsageDescription / NSMicrophoneUsageDescription /
# NSPhotoLibraryUsageDescription unconditionally, and leaves them EMPTY when the corresponding
# privacy options aren't filled in. An empty purpose string is worse than no key at all: App Store
# review flags it, and this game touches none of those APIs. Strip them.
for key in NSCameraUsageDescription NSMicrophoneUsageDescription NSPhotoLibraryUsageDescription; do
	if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
		existing="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)"
		if [ -z "$existing" ]; then
			/usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST"
			echo "  removed empty $key"
		fi
	fi
done

if [ "$MODE" = "export" ]; then
	say "Done — Xcode project at $BUILD_DIR/$SCHEME.xcodeproj"
	exit 0
fi

# ---------------------------------------------------------------------------------------------
say "Archiving (unsigned)"
# Unsigned on purpose. Ian's team has zero registered devices, so an automatic-signing archive
# fails outright; signing is applied later by -exportArchive, which uses cloud-managed
# certificates. See docs/IOS_BUILD.md.
cd "$BUILD_DIR"
rm -rf "$SCHEME.xcarchive"
xcodebuild \
	-project "$SCHEME.xcodeproj" \
	-scheme "$SCHEME" \
	-sdk iphoneos \
	-configuration Release \
	-destination 'generic/platform=iOS' \
	-derivedDataPath ./dd \
	-archivePath "./$SCHEME.xcarchive" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY="" \
	DEVELOPMENT_TEAM="$TEAM_ID" \
	archive \
	| tail -3

[ -d "$SCHEME.xcarchive" ] || { echo "Archive failed." >&2; exit 1; }
echo "  arch: $(lipo -archs "$SCHEME.xcarchive/Products/Applications/$SCHEME.app/$SCHEME")"
echo "  size: $(du -sh "$SCHEME.xcarchive" | cut -f1)"

[ "$MODE" = "archive" ] && { say "Done — archive at $BUILD_DIR/$SCHEME.xcarchive"; exit 0; }

# ---------------------------------------------------------------------------------------------
case "$MODE" in
	ipa)    OPTS="$PROJECT_DIR/ios/ExportOptionsLocal.plist"; say "Exporting signed .ipa" ;;
	upload) OPTS="$PROJECT_DIR/ios/ExportOptions.plist";      say "Uploading to App Store Connect" ;;
	*)      echo "Unknown mode '$MODE' (export|archive|ipa|upload)" >&2; exit 1 ;;
esac

rm -rf ./export
if ! xcodebuild -exportArchive \
	-archivePath "./$SCHEME.xcarchive" \
	-exportOptionsPlist "$OPTS" \
	-exportPath ./export \
	-allowProvisioningUpdates 2>&1 | tail -8
then
	cat >&2 <<'MSG'

Signing failed. Almost always "No Accounts": cloud-managed signing needs a live Xcode account
session, which cannot be created from the command line.

Fix (one-time, Ian):
  Xcode -> Settings -> Accounts -> + -> Apple ID -> sign in
Then re-run:
  tools/build_ios.sh ipa

MSG
	exit 1
fi

say "Done — $BUILD_DIR/export"
ls -la ./export
