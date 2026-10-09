#!/usr/bin/env bash
# Build a committed revision without Local.xcconfig or other untracked files.
# Usage: bash mac/scripts/package-release.sh REF VERSION [OUTPUT_DIRECTORY]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REF="${1:?Pass a committed revision}"
VERSION="${2:?Pass an asset version, e.g. 0.1.0-preview.1}"
[[ "$VERSION" =~ ^[0-9][A-Za-z0-9.-]*$ ]] || exit 2
OUTPUT="${3:-$ROOT/mac/build/releases/$VERSION}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
SHA="$(git -C "$ROOT" rev-parse "$REF^{commit}")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/deai-release.XXXXXX")"
# Rust resolves macOS /var symlinks before embedding generated-source paths.
WORK="$(cd "$WORK" && pwd -P)"
echo "Build workspace: $WORK"
echo "Source revision: $SHA"
mkdir -p "$WORK/source" "$WORK/stage"
git -C "$ROOT" archive "$SHA" | tar -x -C "$WORK/source"

# Keep source paths and the builder's home directory out of the binary.
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=$WORK=/build/deai"$'\x1f'"--remap-path-prefix=$HOME=/build/host"
unset CARGO_TARGET_DIR
bash "$WORK/source/core/scripts/build-apple.sh"
(
    cd "$WORK/source/mac"
    xcodegen
    xcodebuild -project DeAI.xcodeproj -scheme DeAI \
        -configuration Release -derivedDataPath "$WORK/dd" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
        ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' \
        SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
        "OTHER_SWIFT_FLAGS=-file-prefix-map \"$WORK=/build/deai\" -file-prefix-map \"$HOME=/build/host\" -debug-prefix-map \"$WORK=/build/deai\" -debug-prefix-map \"$HOME=/build/host\"" \
        build
)

APP="$WORK/stage/DeAI.app"
ditto "$WORK/dd/Build/Products/Release/DeAI.app" "$APP"
cp "$WORK/source/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$WORK/source/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
printf 'Source: https://github.com/YouAI-Liu/deai-writer\nCommit: %s\nPreview: %s\n' \
    "$SHA" "$VERSION" > "$APP/Contents/Resources/BUILD-INFO.txt"
# Xcode's linker can retain object-file paths in the debug symbol table.
xcrun strip -S "$APP/Contents/MacOS/DeAI"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

ZIP="DeAI-$VERSION-macOS-universal.zip"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$OUTPUT/$ZIP"
(
    cd "$OUTPUT"
    shasum -a 256 "$ZIP" > SHA256SUMS.txt
)
echo "Package: $OUTPUT/$ZIP"
echo "Staged app: $APP"
