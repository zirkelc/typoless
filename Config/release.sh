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
#        xcrun notarytool store-credentials spellbee \
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

NOTARY_PROFILE=${NOTARY_PROFILE:-spellbee}
BUILD=build/release
ARCHIVE="$BUILD/Spellbee.xcarchive"
EXPORTED="$BUILD/export"
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)

if [ -z "$SPARKLE_BIN" ]; then
    echo "Sparkle's tools are not in DerivedData. Build the app once first."
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
echo "==> Archiving $VERSION"
xcodebuild archive \
    -project Spellbee.xcodeproj \
    -scheme Spellbee \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    MARKETING_VERSION="$VERSION"

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

APP="$EXPORTED/Spellbee.app"

echo "==> Notarizing, which waits for Apple and usually takes a few minutes"
ditto -c -k --keepParent "$APP" "$BUILD/Spellbee-notarize.zip"
xcrun notarytool submit "$BUILD/Spellbee-notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# Stapled so the app opens on a machine that is offline the first time it runs.
echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Packaging"
RELEASES=build/releases
mkdir -p "$RELEASES"
ditto -c -k --keepParent "$APP" "$RELEASES/Spellbee-$VERSION.zip"

# generate_appcast signs every archive in the folder with the key from the
# keychain and writes the feed, so the signature and the entry cannot disagree.
echo "==> Writing the appcast"
"$SPARKLE_BIN/generate_appcast" "$RELEASES"

echo
echo "Done. Upload these:"
echo "  $RELEASES/Spellbee-$VERSION.zip"
echo "  $RELEASES/appcast.xml"
echo
echo "The appcast has to end up at the URL in SUFeedURL, which is currently:"
/usr/libexec/PlistBuddy -c "Print SUFeedURL" "$APP/Contents/Info.plist" 2>/dev/null || echo "  (not set)"
