# Sourced by the scripts that need files Xcode keeps outside the repository.
#
#     source Config/derived-data.sh
#     packages=$(source_packages_dir)
#
# Asks Xcode where this project's build folder is rather than searching
# DerivedData for one. A search takes whichever folder the file system lists
# first, and a project that has moved, or been renamed, leaves an old folder
# behind that still matches: the licence notices were once about to be read
# from checkouts nobody updated any more, and the appcast signed with an old
# copy of Sparkle's tools.
#
# Expects to be run from the app folder, which every script that sources this
# ensures first.

source_packages_dir() {
    local build_dir
    build_dir=$(xcodebuild -project Typoless.xcodeproj -scheme Typoless -showBuildSettings 2>/dev/null |
        awk -F' = ' '/^ *BUILD_DIR = /{print $2; exit}')

    if [ -z "$build_dir" ]; then
        echo "Could not ask Xcode for the build folder." >&2
        return 1
    fi

    # BUILD_DIR is <DerivedData>/<project>/Build/Products; the packages sit
    # beside Build.
    local packages="${build_dir%/Build/Products}/SourcePackages"

    if [ ! -d "$packages/checkouts" ]; then
        echo "No package checkouts in $packages. Build the app once first." >&2
        return 1
    fi

    echo "$packages"
}
