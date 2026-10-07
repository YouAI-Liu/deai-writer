#!/usr/bin/env bash
# Builds deai-ffi as a universal static library, generates UniFFI Swift
# bindings, and packages a DeAICore.xcframework for the Mac app.
#
# Outputs:
#   core/build/libdeai_ffi.a        universal (arm64 + x86_64) static lib
#   core/build/swift/DeAICore.swift generated UniFFI bindings
#   core/build/headers/             FFI header + modulemap for the xcframework
#   core/build/DeAICore.xcframework
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$CORE/build"
HEADERS="$BUILD/headers"

# shellcheck disable=SC1091
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

cd "$CORE"

for target in aarch64-apple-darwin x86_64-apple-darwin; do
    cargo build --release -p deai-ffi --target "$target"
done

mkdir -p "$BUILD" "$HEADERS"

lipo -create \
    "$CORE/target/aarch64-apple-darwin/release/libdeai_ffi.a" \
    "$CORE/target/x86_64-apple-darwin/release/libdeai_ffi.a" \
    -output "$BUILD/libdeai_ffi.a"

# Generate Swift bindings in library mode (extracts metadata embedded in the lib).
cargo run --release -p deai-ffi --bin uniffi-bindgen -- \
    generate \
    --library "$CORE/target/aarch64-apple-darwin/release/libdeai_ffi.a" \
    --config "$CORE/crates/deai-ffi/uniffi.toml" \
    --language swift \
    --out-dir "$BUILD/swift"

cp "$BUILD/swift/DeAICoreFFI.h" "$HEADERS/"
cp "$BUILD/swift/DeAICoreFFI.modulemap" "$HEADERS/module.modulemap"

rm -rf "$BUILD/DeAICore.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD/libdeai_ffi.a" \
    -headers "$HEADERS" \
    -output "$BUILD/DeAICore.xcframework"

echo "Done: $BUILD/DeAICore.xcframework"
echo "Swift bindings: $BUILD/swift/DeAICore.swift"
