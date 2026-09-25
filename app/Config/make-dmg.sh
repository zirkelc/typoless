#!/bin/bash
#
# Builds the drag-and-drop disk image for a release.
#
#     ./Config/make-dmg.sh 0.2.0 [path/to/Typoless.app]
#
# The app is expected to be signed, notarized and stapled already, which is
# what release.sh has done by the time it calls this. The image itself is
# signed and notarized too, separately from the app inside it: Gatekeeper
# judges the disk image a person downloads, and an unnotarized one is refused
# before the app in it is ever looked at.
#
# The zip stays the artefact Sparkle updates from. An update should not ask
# anybody to mount anything, and the deltas are built from the archives. So a
# release carries both: a disk image for a person arriving at the website, a zip
# for the updater.
#
# Set SKIP_NOTARIZE=1 to build the image without the Apple round trip, which is
# useful when only the window layout is being tried out. Such an image is not
# fit to publish.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-}
if [ -z "$VERSION" ]; then
    echo "usage: $0 <version> [app]   e.g. $0 0.2.0"
    exit 2
fi

APP=${2:-build/release/export/Typoless.app}
if [ ! -d "$APP" ]; then
    echo "No app at $APP. Run Config/release.sh, or name the app to package."
    exit 1
fi

NOTARY_PROFILE=${NOTARY_PROFILE:-typoless}
# Deliberately not build/releases: Sparkle's generate_appcast treats every archive
# in that folder as a release of its own, and a disk image counts as one, so a
# dmg left there would be written into the feed beside the zip.
OUT=build/dmg
DMG="$PWD/$OUT/Typoless-$VERSION.dmg"
VOLUME="Typoless"

# A fresh temporary folder rather than a path that has to be emptied first, so
# nothing is ever deleted to make room for this build.
WORK=$(mktemp -d /tmp/typoless-dmg.XXXXXX)
RW="$WORK/rw.dmg"

echo "==> Building a read-write image"
# Sized from the app plus room for the folder settings Finder writes. An image
# sized exactly to its contents can run out of space while being laid out.
SIZE_KB=$(( $(du -sk "$APP" | cut -f1) + 20000 ))
hdiutil create -size "${SIZE_KB}k" -fs HFS+ -volname "$VOLUME" -ov "$RW" >/dev/null

# -nobrowse keeps it out of the Finder sidebar, -noautoopen stops a window
# opening before the layout below asks for one.
MOUNT=$(hdiutil attach "$RW" -nobrowse -noautoopen |
    grep -oE '/Volumes/.*$' | tail -1)
if [ -z "$MOUNT" ]; then
    echo "The image would not mount."
    exit 1
fi

# Unmounted on the way out however this ends, because a left-behind mount makes
# the next run fail on a volume name that is already taken.
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT

echo "==> Filling it"
ditto "$APP" "$MOUNT/Typoless.app"

# The whole point of the image: the folder beside the app is the real
# /Applications, so moving one onto the other installs it.
ln -s /Applications "$MOUNT/Applications"

echo "==> Laying out the window"
# Finder is the only thing that can write these view settings, so this asks it
# to. It needs permission to control the Finder the first time, and it is not
# available at all on a machine without a session, so a failure here is a
# warning: the image still works, it just opens in whatever view is default.
osascript <<'APPLESCRIPT' >/dev/null 2>&1 || echo "    (Finder would not lay out the window, which is cosmetic)"
tell application "Finder"
    tell disk "Typoless"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {240, 160, 840, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set position of item "Typoless.app" of container window to {150, 185}
        set position of item "Applications" of container window to {450, 185}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# The app's own icon for the mounted volume. The C attribute is what tells the
# Finder to use it; without that the file is just a file. Set after the layout
# above, not before: Finder removes both the file and the attribute when it
# writes the folder settings of a volume it finds them on.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || echo "    (could not set the volume icon, which is cosmetic)"

# Written out before the image is closed, or the settings may not reach it.
sync

hdiutil detach "$MOUNT" -quiet
trap - EXIT

echo "==> Compressing"
mkdir -p "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null

echo "==> Signing the image"
IDENTITY=$(security find-identity -v -p codesigning |
    grep "Developer ID Application" | head -1 | grep -oE '[0-9A-F]{40}')
if [ -z "$IDENTITY" ]; then
    echo "No Developer ID Application certificate in the keychain, so the image cannot be signed."
    exit 1
fi
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo
    echo "Built $DMG without notarizing. Do not publish it."
    exit 0
fi

echo "==> Notarizing the image, which waits for Apple"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# Stapled so the image opens on a machine that is offline.
echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Built $DMG"
