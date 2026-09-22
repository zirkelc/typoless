#!/bin/bash
#
# Builds, signs, notarizes and packages a release, then writes the appcast.
#
#     ./Config/release.sh 0.2.0
#
# Needs, once, before this works at all:
#
#   1. A Developer ID Application certificate in the login keychain, belonging
#      to the team in DEVELOPMENT_TEAM. An Apple Development certificate is not
#      one: it signs for your own machines and Gatekeeper refuses it anywhere
#      else.
#   2. Notarization credentials stored under the profile named below:
#        xcrun notarytool store-credentials typoless \
#            --apple-id <your-apple-id> --team-id <team> --password <app-specific>
#      The password is an app-specific one from appleid.apple.com, not the
#      account password.
#   3. A Sparkle signing key in the keychain, whose public half is already in
#      the built app as SUPublicEDKey. Generated once with Sparkle's
#      generate_keys; if it is ever lost, no existing install can be updated
#      again, by anyone, ever.
#
# Notarization is not optional here even though this app is not sandboxed:
# Gatekeeper refuses an unnotarized app on first launch, and Sparkle installs
# over the running app, so an unnotarized update fails at the last step rather
# than the first.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-}
if [ -z "$VERSION" ]; then
    echo "usage: $0 <version>   e.g. $0 0.2.0"
    exit 2
fi

NOTARY_PROFILE=${NOTARY_PROFILE:-typoless}
BUILD=build/release
ARCHIVE="$BUILD/Typoless.xcarchive"
EXPORTED="$BUILD/export"
RELEASES=build/releases

# The build number, which is what Sparkle compares to decide whether a release
# is newer: the version string is for people, CFBundleVersion is for Sparkle.
# Every release used to carry build 1, so no release could ever be offered as
# newer than the one installed. The commit count only grows on this branch;
# set BUILD_NUMBER to release twice from the same commit.
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD)}

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "BUILD_NUMBER must be a whole number, not '$BUILD_NUMBER'."
    exit 2
fi

if [ -f "$RELEASES/appcast.xml" ]; then
    LATEST=$(grep -o 'sparkle:version="[0-9]*"' "$RELEASES/appcast.xml" | grep -o '[0-9]*' | sort -n | tail -1)
    if [ -n "$LATEST" ] && [ "$BUILD_NUMBER" -le "$LATEST" ]; then
        echo "Build $BUILD_NUMBER is not newer than build $LATEST in the appcast, so no one would be offered it."
        echo "Commit first, or set BUILD_NUMBER higher than $LATEST."
        exit 2
    fi
fi

source Config/derived-data.sh
SPARKLE_BIN="$(source_packages_dir)/artifacts/sparkle/Sparkle/bin"

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "Sparkle's tools are not in $SPARKLE_BIN. Build the app once first."
    exit 1
fi

echo "==> Checking for a Developer ID certificate"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "No Developer ID Application certificate in the keychain."
    echo "Xcode > Settings > Accounts > your team > Manage Certificates > + > Developer ID Application"
    exit 1
fi

# Signing is deliberately left alone here and handled by the export below.
# Overriding CODE_SIGN_IDENTITY on the command line applies it to every target
# in the build, including the dozen that arrive with the packages, and each of
# those then fails for want of a development team it has no reason to have.
echo "==> Archiving $VERSION (build $BUILD_NUMBER)"
xcodebuild archive \
    -project Typoless.xcodeproj \
    -scheme Typoless \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "==> Exporting"
cat > "$BUILD/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>D568Q9VY3L</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORTED" \
    -exportOptionsPlist "$BUILD/export-options.plist"

APP="$EXPORTED/Typoless.app"

# The feed is in the built app, from the Release build setting. The downloads
# go beside it, so the two are read from one value rather than kept in step by
# hand. Always ends in a slash: generate_appcast resolves each file name
# against this, and without one it would drop the last folder of the address.
FEED_URL=$(/usr/libexec/PlistBuddy -c "Print SUFeedURL" "$APP/Contents/Info.plist" 2>/dev/null || true)

if [ -z "$FEED_URL" ]; then
    echo "The exported app has no SUFeedURL, so it could never find an update. Is TYPOLESS_FEED_URL set for Release?"
    exit 1
fi

DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-${FEED_URL%/*}/releases/}"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX%/}/"

echo "==> Notarizing, which waits for Apple and usually takes a few minutes"
ditto -c -k --keepParent "$APP" "$BUILD/Typoless-notarize.zip"
xcrun notarytool submit "$BUILD/Typoless-notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# Stapled so the app opens on a machine that is offline the first time it runs.
echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Packaging"
mkdir -p "$RELEASES"
ditto -c -k --keepParent "$APP" "$RELEASES/Typoless-$VERSION.zip"

# generate_appcast signs every archive in the folder with the key from the
# keychain and writes the feed, so the signature and the entry cannot disagree.
echo "==> Writing the appcast"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DOWNLOAD_PREFIX" "$RELEASES"

echo
echo "Done. Upload these:"
echo "  $RELEASES/Typoless-$VERSION.zip  ->  ${DOWNLOAD_PREFIX}Typoless-$VERSION.zip"
echo "  $RELEASES/appcast.xml  ->  $FEED_URL"
