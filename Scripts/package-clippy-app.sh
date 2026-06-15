#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-debug}"
build_dir="$repo_root/.build/$configuration"
app_dir="$build_dir/Clippy.app"

cd "$repo_root"
swift build ${configuration:+--configuration "$configuration"}

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources/Characters"
cp "$build_dir/Clippy" "$app_dir/Contents/MacOS/Clippy"
cp "$build_dir/ClippyMCP" "$app_dir/Contents/MacOS/ClippyMCP"
cua_driver_source="${CLIPPY_CUA_DRIVER:-}"
if [ -z "$cua_driver_source" ]; then
  for candidate in \
    "$HOME/.local/bin/cua-driver" \
    "/Applications/CuaDriver.app/Contents/MacOS/cua-driver"
  do
    if [ -x "$candidate" ]; then
      cua_driver_source="$candidate"
      break
    fi
  done
fi
if [ -z "$cua_driver_source" ] || [ ! -x "$cua_driver_source" ]; then
  echo "ERROR: cua-driver is required for product computer use. Install it or set CLIPPY_CUA_DRIVER=/path/to/cua-driver." >&2
  exit 1
fi
cp "$cua_driver_source" "$app_dir/Contents/Helpers/ClippyComputerUseRuntime"
chmod 755 "$app_dir/Contents/Helpers/ClippyComputerUseRuntime"
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
  <string>ai.companion.clippy</string>
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

# Code signing. A STABLE signing identity is what makes macOS keep TCC grants
# (Screen Recording, Microphone, Accessibility) across rebuilds. Ad-hoc signatures
# key on the cdhash, which changes every build, so the OS forgets the grant and
# re-prompts forever. Signing with the Developer ID (stable, keyed to the Team ID)
# fixes that: grant once, it sticks. Override with CODESIGN_IDENTITY=… if needed;
# set CODESIGN_IDENTITY=- to fall back to ad-hoc.
codesign_identity="${CODESIGN_IDENTITY:-Developer ID Application: Companion, Inc. (5LYD7HDS6X)}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$codesign_identity" || [ "$codesign_identity" = "-" ]; then
  # Sign inside-out: nested helper first, then the bundle seals everything.
  # Hardened runtime + a secure timestamp are REQUIRED for notarization; the
  # entitlements re-grant the mic + Apple Events that hardened runtime would
  # otherwise block. (Ad-hoc identity "-" can't timestamp, so skip it there.)
  ts_flag="--timestamp"; [ "$codesign_identity" = "-" ] && ts_flag="--timestamp=none"
  codesign --force $ts_flag --options runtime --sign "$codesign_identity" "$app_dir/Contents/MacOS/ClippyMCP"
  codesign --force $ts_flag --options runtime \
    --identifier ai.companion.clippy \
    --sign "$codesign_identity" "$app_dir/Contents/Helpers/ClippyComputerUseRuntime"
  codesign --force $ts_flag --options runtime \
    --entitlements "$repo_root/Resources/Clippy.entitlements" \
    --sign "$codesign_identity" "$app_dir"
  codesign --verify --strict "$app_dir"
  echo "signed with: $codesign_identity"
else
  echo "WARNING: signing identity not found ('$codesign_identity') — leaving ad-hoc; TCC grants will NOT persist across rebuilds." >&2
fi

echo "$app_dir"
