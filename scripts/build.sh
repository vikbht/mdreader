#!/bin/bash

# ==========================================================================
# MDReader Shared Build Script (used by install.sh and GitHub Actions)
# Usage: ./scripts/build.sh [--universal]
# ==========================================================================

set -euo pipefail

UNIVERSAL=false
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=true ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: $0 [--universal]" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# 1. Environment checks
for tool in swiftc sips iconutil codesign; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: required macOS tool '$tool' not found." >&2
        exit 1
    fi
done

if [ "$UNIVERSAL" = true ] && ! command -v lipo &> /dev/null; then
    echo "Error: 'lipo' not found (required for --universal builds)." >&2
    exit 1
fi

# 2. Clean previous build artifacts
rm -rf build/ AppIcon.iconset/ AppIcon.icns

BUILD_DIR="build/MDReader.app"
mkdir -p "${BUILD_DIR}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/Contents/Resources"

# 3. Generate native multi-resolution .icns icon
if [ -f "src/resources/AppIcon.png" ]; then
    mkdir -p AppIcon.iconset
    sips -s format png -z 16 16     src/resources/AppIcon.png --out AppIcon.iconset/icon_16x16.png >/dev/null
    sips -s format png -z 32 32     src/resources/AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png >/dev/null
    sips -s format png -z 32 32     src/resources/AppIcon.png --out AppIcon.iconset/icon_32x32.png >/dev/null
    sips -s format png -z 64 64     src/resources/AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png >/dev/null
    sips -s format png -z 128 128   src/resources/AppIcon.png --out AppIcon.iconset/icon_128x128.png >/dev/null
    sips -s format png -z 256 256   src/resources/AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png >/dev/null
    sips -s format png -z 256 256   src/resources/AppIcon.png --out AppIcon.iconset/icon_256x256.png >/dev/null
    sips -s format png -z 512 512   src/resources/AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png >/dev/null
    sips -s format png -z 512 512   src/resources/AppIcon.png --out AppIcon.iconset/icon_512x512.png >/dev/null
    sips -s format png -z 1024 1024 src/resources/AppIcon.png --out AppIcon.iconset/icon_512x512@2x.png >/dev/null

    iconutil -c icns AppIcon.iconset
    mv AppIcon.icns "${BUILD_DIR}/Contents/Resources/AppIcon.icns"
    rm -rf AppIcon.iconset
fi

# 4. Compile Swift binary (Universal arm64 + x86_64 when SDK supports both, else host arch)
if [ "$UNIVERSAL" = true ]; then
    echo "Compiling Universal binary (arm64 + x86_64)..."
    swiftc -O -target arm64-apple-macosx12.0 src/main.swift -o build/MDReader-arm64
    if swiftc -O -target x86_64-apple-macosx12.0 src/main.swift -o build/MDReader-x86_64 2>/dev/null; then
        lipo -create build/MDReader-arm64 build/MDReader-x86_64 -output "${BUILD_DIR}/Contents/MacOS/MDReader"
        rm -f build/MDReader-arm64 build/MDReader-x86_64
    else
        echo "Note: Host macOS SDK does not include x86_64 Swift compatibility slices; building arm64 binary."
        mv build/MDReader-arm64 "${BUILD_DIR}/Contents/MacOS/MDReader"
        rm -f build/MDReader-x86_64
    fi
else
    echo "Compiling native Swift binary..."
    swiftc -O src/main.swift -o "${BUILD_DIR}/Contents/MacOS/MDReader"
fi

# 5. Copy Info.plist and offline resources
cp Info.plist "${BUILD_DIR}/Contents/"
cp src/resources/template.html "${BUILD_DIR}/Contents/Resources/"
cp src/resources/style.css "${BUILD_DIR}/Contents/Resources/"
cp src/resources/marked.min.js "${BUILD_DIR}/Contents/Resources/"
cp src/resources/purify.min.js "${BUILD_DIR}/Contents/Resources/"
cp src/resources/highlight.min.js "${BUILD_DIR}/Contents/Resources/"
cp src/resources/mermaid.min.js "${BUILD_DIR}/Contents/Resources/"
cp -R src/resources/katex "${BUILD_DIR}/Contents/Resources/"

# 6. Apply deep ad-hoc code signature
codesign --force --deep --sign - "${BUILD_DIR}"

echo "Built ${BUILD_DIR} successfully."
