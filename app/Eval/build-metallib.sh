#!/bin/bash
#
# Builds MLX's Metal kernels so the eval can run as a plain SwiftPM executable.
#
# Xcode compiles the `.metal` files inside a package for you; `swift build` does
# not, so an executable built with SwiftPM starts and then fails on the first
# array with "Failed to load the default metallib". MLX looks for
# `mlx.metallib` next to the binary before anything else, which is where this
# puts it.
#
# Takes a couple of minutes the first time and is then skipped, so it is cheap
# to call before every run.
#
#     ./build-metallib.sh [debug|release]

set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
OUTPUT=".build/$CONFIGURATION/mlx.metallib"
SOURCES=".build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"

if [ ! -d "$SOURCES" ]; then
    echo "MLX is not checked out yet. Run 'swift build -c $CONFIGURATION' first." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

if [ -f "$OUTPUT" ] && [ "$OUTPUT" -nt "$SOURCES" ]; then
    echo "$OUTPUT is up to date"
    exit 0
fi

SCRATCH=$(mktemp -d)
trap 'trash "$SCRATCH" 2>/dev/null || true' EXIT

echo "compiling MLX Metal kernels"
AIR=()
while IFS= read -r shader; do
    object="$SCRATCH/$(echo "${shader#"$SOURCES/"}" | tr '/' '_').air"
    xcrun metal -std=metal3.1 -O2 -c "$shader" -I "$SOURCES" -o "$object"
    AIR+=("$object")
done < <(find "$SOURCES" -name '*.metal' | sort)

echo "linking ${#AIR[@]} kernels into $OUTPUT"
xcrun metallib "${AIR[@]}" -o "$OUTPUT"
