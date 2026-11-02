#!/bin/bash
#
# Runs the unit tests with the same Xcode setup the release uses.
#
#     ./Config/test.sh
#     ./Config/test.sh -only-testing:TypolessTests/LanguageDetectorTests
#
# Any argument is passed on to xcodebuild. Needs no model and no network once
# the packages are resolved.

set -euo pipefail
cd "$(dirname "$0")/.."

source Config/derived-data.sh
prepare_xcode

xcodebuild test "${XCODE_FLAGS[@]}" -destination 'platform=macOS' "$@"
