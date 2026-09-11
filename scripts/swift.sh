#!/bin/sh
# Keep compiler and SwiftPM caches inside the checkout, including in restricted environments.
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/swiftpm-cache .build/swiftpm-config .build/swiftpm-security
if [ "${POCKET_DISABLE_SWIFTPM_SANDBOX:-0}" = 1 ]; then
    set -- "$@" --disable-sandbox
fi
exec swift "$@" --cache-path "$PWD/.build/swiftpm-cache" --config-path "$PWD/.build/swiftpm-config" --security-path "$PWD/.build/swiftpm-security"
