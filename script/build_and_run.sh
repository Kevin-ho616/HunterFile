#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="OpenEagle"
BUNDLE_ID="com.kevin.OpenEagle"
if [[ "$MODE" == "--qa" ]]; then APP_NAME="OpenEagleQA"; BUNDLE_ID="com.kevin.OpenEagle.QA"; fi
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONFIGURATION="debug"
if [[ "$MODE" == "--release" || "$MODE" == "--install" ]]; then CONFIGURATION="release"; fi

if pgrep -x "$APP_NAME" >/dev/null; then
    pkill -TERM -x "$APP_NAME"
    for attempt in {1..20}; do
        if ! pgrep -x "$APP_NAME" >/dev/null; then break; fi
        sleep 0.1
    done
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "OpenEagle is still running. Close it before rebuilding." >&2
        exit 1
    fi
fi

swift build -c "$CONFIGURATION" --product OpenEagle
BUILD_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/OpenEagle"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -f "$(dirname "$BUILD_BINARY")/libCLiteRTLM_mac.dylib" "$APP_BUNDLE/Contents/Frameworks/"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --force --sign - "$APP_BUNDLE/Contents/Frameworks/libCLiteRTLM_mac.dylib"
ditto LICENSES "$APP_BUNDLE/Contents/Resources/LICENSES"
cp docs/USER-GUIDE.md "$APP_BUNDLE/Contents/Resources/USER-GUIDE.md"
cp docs/LOCAL-AI.md "$APP_BUNDLE/Contents/Resources/LOCAL-AI.md"
cp docs/AUTOMATION.md "$APP_BUNDLE/Contents/Resources/AUTOMATION.md"
cp script/openeagle.py "$APP_BUNDLE/Contents/Resources/openeagle.py"
ditto browser-extension "$APP_BUNDLE/Contents/Resources/browser-extension"
ditto plugins "$APP_BUNDLE/Contents/Resources/plugins"
swift script/make_icon.swift "$ROOT_DIR/dist"
cp "$ROOT_DIR/dist/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OpenEagle</string>
<key>CFBundleIdentifier</key><string>com.kevin.OpenEagle</string>
<key>CFBundleName</key><string>OpenEagle</string>
<key>CFBundleDisplayName</key><string>OpenEagle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>OpenEagle Library</string>
<key>CFBundleTypeRole</key><string>Editor</string>
<key>LSHandlerRank</key><string>Owner</string>
<key>LSItemContentTypes</key><array><string>com.kevin.openeagle.library</string></array>
<key>LSTypeIsPackage</key><true/>
</dict><dict>
<key>CFBundleTypeName</key><string>OpenEagle Asset Pack</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Owner</string>
<key>LSItemContentTypes</key><array><string>com.kevin.openeagle.asset-pack</string></array>
<key>LSTypeIsPackage</key><true/>
</dict></array>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>com.kevin.openeagle.library</string>
<key>UTTypeDescription</key><string>OpenEagle Library</string>
<key>UTTypeConformsTo</key><array><string>com.apple.package</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>openeagle</string></array></dict>
</dict><dict>
<key>UTTypeIdentifier</key><string>com.kevin.openeagle.asset-pack</string>
<key>UTTypeDescription</key><string>OpenEagle Asset Pack</string>
<key>UTTypeConformsTo</key><array><string>com.apple.package</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>openeaglepack</string></array></dict>
</dict><dict>
<key>UTTypeIdentifier</key><string>com.kevin.openeagle.folder-move</string>
<key>UTTypeDescription</key><string>OpenEagle Folder Move</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP_BUNDLE"
if [[ "$MODE" == "--qa" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName OpenEagleQA" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName OpenEagleQA" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations:0" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Delete :UTExportedTypeDeclarations:0" "$APP_BUNDLE/Contents/Info.plist"
    codesign --force --sign - "$APP_BUNDLE"
    mkdir -p "$ROOT_DIR/test-output"
    /usr/bin/open -n "$APP_BUNDLE" --args --library "$ROOT_DIR/test-output/QA.openeagle" --create-library
    exit 0
fi
case "$MODE" in
    run|--release) /usr/bin/open -n "$APP_BUNDLE" ;;
    --install)
        INSTALLED_BUNDLE="$HOME/Applications/OpenEagle.app"
        if [[ -e "$INSTALLED_BUNDLE" ]]; then
            EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_BUNDLE/Contents/Info.plist")"
            if [[ "$EXISTING_ID" != "$BUNDLE_ID" ]]; then echo "Refusing to replace an unrelated app: $INSTALLED_BUNDLE" >&2; exit 1; fi
        fi
        mkdir -p "$HOME/Applications"
        ditto "$APP_BUNDLE" "$INSTALLED_BUNDLE"
        codesign --verify --deep --strict "$INSTALLED_BUNDLE"
        /usr/bin/open -n "$INSTALLED_BUNDLE"
        echo "Installed: $INSTALLED_BUNDLE"
        ;;
    --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "OpenEagle build and launch verified: $APP_BUNDLE" ;;
    --build) echo "$APP_BUNDLE" ;;
    --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
    --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "OpenEagle"' ;;
    --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.kevin.OpenEagle"' ;;
    *) echo "Usage: $0 [--verify|--build|--release|--install|--qa|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
