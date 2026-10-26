#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo "This validation requires macOS and Xcode." >&2
    exit 2
fi
if ! xcodebuild -version; then
    echo "Full Xcode is required for XCTest and the iOS simulator SDK. Install Xcode and select its developer directory before rerunning." >&2
    exit 2
fi
swift test --package-path Core -c debug
swift test --package-path Core -c release
# Build against the simulator SDK without requiring an installed simulator runtime.
# This compiles the app; launching it still requires a runtime.
xcodebuild -project ProofCamResearch.xcodeproj -target ProofCamResearch \
    -configuration Release -sdk iphonesimulator ARCHS="$(uname -m)" \
    SYMROOT="$PWD/DerivedData/Build/Products" \
    OBJROOT="$PWD/DerivedData/Build/Intermediates.noindex" \
    CODE_SIGNING_ALLOWED=NO build
