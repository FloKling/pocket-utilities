#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# CLT ships Swift Testing but SwiftPM does not automatically find its framework directory.
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [ -d "$FRAMEWORKS/Testing.framework" ]; then
    exec ./scripts/swift.sh test --arch arm64 --disable-xctest --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$(dirname "$FRAMEWORKS")/usr/lib" "$@"
fi
exec ./scripts/swift.sh test --arch arm64 --disable-xctest --enable-swift-testing "$@"
