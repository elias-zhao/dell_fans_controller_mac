#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    ACTIVE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$ACTIVE_DEV_DIR" != *"/Xcode.app/"* ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
fi

CONFIG="release"
UNIVERSAL=true
CREATE_PACKAGE=true

for arg in "$@"; do
    case "$arg" in
        --debug)
            CONFIG="debug"
            UNIVERSAL=false
            CREATE_PACKAGE=false
            ;;
        --native)
            UNIVERSAL=false
            ;;
        --no-package)
            CREATE_PACKAGE=false
            ;;
        -h|--help)
            cat <<'EOF'
Usage: ./scripts/build-app.sh [options]
  (default)     Build Universal (arm64 + x86_64) release .app, .zip, and .dmg
  --debug       Build native debug .app only
  --native      Build native architecture release .app
  --no-package  Skip .zip and .dmg creation
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

EXECUTABLE=""
ARCH_LABEL="$(uname -m)"

if [[ "$UNIVERSAL" == true ]]; then
    ARCH_LABEL="universal"
    echo "Building DellFansController ($CONFIG, universal: arm64 + x86_64)..."
    if swift build -c "$CONFIG" --arch arm64 --arch x86_64; then
        BIN_DIR="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
        if [[ -x "$BIN_DIR/DellFansController" ]]; then
            EXECUTABLE="$BIN_DIR/DellFansController"
        fi
    fi

    if [[ -z "$EXECUTABLE" ]]; then
        echo "Fallback: building arm64 and x86_64 separately and merging with lipo..."
        swift build -c "$CONFIG" --arch arm64
        swift build -c "$CONFIG" --arch x86_64
        ARM64_BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/DellFansController"
        X86_BIN="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/DellFansController"
        MERGED_BIN="$ROOT_DIR/build/DellFansController-universal"
        mkdir -p "$ROOT_DIR/build"
        lipo -create "$ARM64_BIN" "$X86_BIN" -output "$MERGED_BIN"
        EXECUTABLE="$MERGED_BIN"
    fi
else
    echo "Building DellFansController ($CONFIG, native: $ARCH_LABEL)..."
    swift build -c "$CONFIG"
    BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
    EXECUTABLE="$BIN_DIR/DellFansController"
fi

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Error: executable not found at $EXECUTABLE" >&2
    exit 1
fi

APP_BUNDLE="$ROOT_DIR/build/DellFansController.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/DellFansController"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
chmod +x "$APP_BUNDLE/Contents/MacOS/DellFansController"

if [[ "$EXECUTABLE" == "$ROOT_DIR/build/DellFansController-universal" ]]; then
    rm -f "$EXECUTABLE"
fi

echo "Signing $APP_BUNDLE (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

if [[ "$CREATE_PACKAGE" == true ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist")"
    ZIP_PATH="$ROOT_DIR/build/DellFansController-v${VERSION}-macOS-${ARCH_LABEL}.zip"
    DMG_PATH="$ROOT_DIR/build/DellFansController-v${VERSION}-macOS-${ARCH_LABEL}.dmg"

    echo "Creating ZIP archive: $ZIP_PATH"
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    echo "Creating DMG image: $DMG_PATH"
    DMG_STAGE="$(mktemp -d)"
    trap 'rm -rf "$DMG_STAGE"' EXIT
    cp -R "$APP_BUNDLE" "$DMG_STAGE/"
    ln -s /Applications "$DMG_STAGE/Applications"
    rm -f "$DMG_PATH"
    hdiutil create -volname "Dell Fans Controller" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
    rm -rf "$DMG_STAGE"
    trap - EXIT

    echo "Packages ready:"
    echo "  - $ZIP_PATH"
    echo "  - $DMG_PATH"
fi

echo "Done: $APP_BUNDLE"
