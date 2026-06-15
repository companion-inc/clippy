#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-debug}"
build_dir="$repo_root/.build/$configuration"
app_dir="$build_dir/Clippy.app"

cd "$repo_root"
xcrun swift build ${configuration:+--configuration "$configuration"}

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/Characters"
cp "$build_dir/Clippy" "$app_dir/Contents/MacOS/Clippy"
cp "$build_dir/ClippyMCP" "$app_dir/Contents/MacOS/ClippyMCP"
cp -R "$repo_root/Resources/Characters/Clippy" "$app_dir/Contents/Resources/Characters/Clippy"
cp "$repo_root/Resources/Clippy.icns" "$app_dir/Contents/Resources/Clippy.icns"
mkdir -p "$app_dir/Contents/Resources/Fonts"
cp "$repo_root"/Resources/Fonts/*.ttf "$app_dir/Contents/Resources/Fonts/" 2>/dev/null || true

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Clippy</string>
  <key>CFBundleExecutable</key>
  <string>Clippy</string>
  <key>CFBundleIconFile</key>
  <string>Clippy</string>
  <key>CFBundleIdentifier</key>
  <string>local.clippy.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Clippy</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>ATSApplicationFontsPath</key>
  <string>Fonts</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Clippy listens to your microphone so you can talk to it.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Clippy uses speech recognition to transcribe what you say.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Clippy looks at your screen so it can point things out and help.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Clippy uses Apple Events to help drive apps you ask it to operate.</string>
</dict>
</plist>
PLIST

echo "$app_dir"
