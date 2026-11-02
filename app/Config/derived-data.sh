# Sourced by every script that runs xcodebuild or needs files Xcode keeps
# outside the repository.
#
#     source Config/derived-data.sh
#     prepare_xcode
#     xcodebuild build "${XCODE_FLAGS[@]}"
#     packages=$(source_packages_dir)
#
# An Xcode update used to break the next build in two ways, both far from
# their cause. The build folder still held modules the old compiler had made,
# and the new one refused them with "Unable to resolve Swift module dependency
# to a compatible module: 'SwiftSyntax'". And the update dropped the Metal
# toolchain, which MLX needs for its shaders, so the build stopped at the first
# .metal file.
#
# So the build folder is named for the Xcode build that fills it. A new Xcode
# starts in a folder of its own and never reads what the old one left, and the
# old folder is only named, never deleted, so nothing is lost by updating.
# The folder is also given to xcodebuild rather than asked of it, so every
# script reads the packages from the folder the build wrote to.
#
# Expects to be run from the app folder, which every script that sources this
# ensures first.

XCODE_BUILD=$(xcodebuild -version 2>/dev/null | awk '/Build version/{print $3}')

if [ -z "$XCODE_BUILD" ]; then
    echo "Could not ask xcodebuild for its version. Is Xcode installed and selected?" >&2
    return 1 2>/dev/null || exit 1
fi

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Typoless-Xcode-$XCODE_BUILD"

# The plug-ins and macros come from the packages and would otherwise each wait
# for a click in Xcode that a script cannot give.
XCODE_FLAGS=(
    -project Typoless.xcodeproj
    -scheme Typoless
    -derivedDataPath "$DERIVED_DATA"
    -skipPackagePluginValidation
    -skipMacroValidation
)

# Makes this Xcode able to build the app, and says what it did.
prepare_xcode() {
    echo "==> Building with Xcode $XCODE_BUILD into $DERIVED_DATA"

    if ! xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: installed"; then
        echo "==> This Xcode has no Metal toolchain, which MLX needs. Downloading it (about 850 MB)."
        xcodebuild -downloadComponent MetalToolchain
    fi

    # Before anything looks for Sparkle's tools, which arrive with the packages.
    xcodebuild -resolvePackageDependencies "${XCODE_FLAGS[@]}" >/dev/null

    local stale
    stale=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -name 'Typoless-Xcode-*' \
        ! -name "Typoless-Xcode-$XCODE_BUILD" 2>/dev/null || true)

    if [ -n "$stale" ]; then
        echo "==> Build folders from other Xcode builds, safe to delete:"
        echo "$stale" | sed 's/^/    /'
    fi
}

source_packages_dir() {
    local packages="$DERIVED_DATA/SourcePackages"

    if [ ! -d "$packages/checkouts" ]; then
        echo "No package checkouts in $packages. Run prepare_xcode first." >&2
        return 1
    fi

    echo "$packages"
}
