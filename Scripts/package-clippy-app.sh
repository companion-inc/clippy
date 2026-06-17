#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-debug}"
build_dir="$repo_root/.build/$configuration"
app_dir="$build_dir/Clippy.app"
version="${CLIPPY_VERSION:-}"
if [ -z "$version" ]; then
  ref_name="${GITHUB_REF_NAME:-}"
  if [[ "$ref_name" == v* ]]; then
    version="${ref_name#v}"
  else
    version="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
  fi
fi
version="${version:-0.1.0}"
build_number="${CLIPPY_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
if [ -z "$build_number" ]; then
  build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi
sparkle_feed_url="${CLIPPY_SPARKLE_FEED_URL:-https://github.com/companion-inc/clippy/releases/latest/download/appcast.xml}"
sparkle_public_ed_key="${CLIPPY_SPARKLE_PUBLIC_ED_KEY:-p/STOfduNWVMNYn1sjYX3pbM5PnywVU/8WrGUJjpoAI=}"

cd "$repo_root"
swift build ${configuration:+--configuration "$configuration"}

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources/Characters"
cp "$build_dir/Clippy" "$app_dir/Contents/MacOS/Clippy"
cp "$build_dir/ClippyMCP" "$app_dir/Contents/MacOS/ClippyMCP"
sparkle_framework=""
for candidate in \
  "$build_dir/Sparkle.framework" \
  "$repo_root/.build/arm64-apple-macosx/$configuration/Sparkle.framework" \
  "$repo_root/.build/x86_64-apple-macosx/$configuration/Sparkle.framework"
do
  if [ -d "$candidate" ]; then
    sparkle_framework="$candidate"
    break
  fi
done
if [ -z "$sparkle_framework" ]; then
  sparkle_framework="$(find "$repo_root/.build" -path '*/Sparkle.framework' -type d | head -n 1 || true)"
fi
if [ -z "$sparkle_framework" ] || [ ! -d "$sparkle_framework" ]; then
  echo "ERROR: Sparkle.framework was not produced by SwiftPM." >&2
  exit 1
fi
cp -R "$sparkle_framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_dir/Contents/MacOS/Clippy" 2>/dev/null || true
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

cat > "$app_dir/Contents/Info.plist" <<PLIST
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
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build_number</string>
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
  <key>SUFeedURL</key>
  <string>$sparkle_feed_url</string>
  <key>SUPublicEDKey</key>
  <string>$sparkle_public_ed_key</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SURequireSignedFeed</key>
  <true/>
</dict>
</plist>
PLIST

# Code signing. A STABLE signing identity is what makes macOS keep TCC grants
# (Accessibility, Screen Recording, Full Disk Access, Microphone) across rebuilds. Ad-hoc signatures
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
  while IFS= read -r nested_bundle; do
    codesign --force $ts_flag --options runtime --sign "$codesign_identity" "$nested_bundle"
  done < <(find "$app_dir/Contents/Frameworks/Sparkle.framework" -depth \( -name '*.xpc' -o -name '*.app' \) -type d)
  if [ -x "$app_dir/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" ]; then
    codesign --force $ts_flag --options runtime --sign "$codesign_identity" "$app_dir/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  fi
  codesign --force $ts_flag --options runtime --sign "$codesign_identity" "$app_dir/Contents/Frameworks/Sparkle.framework"
  codesign --force $ts_flag --options runtime --sign "$codesign_identity" "$app_dir/Contents/MacOS/ClippyMCP"
  codesign --force $ts_flag --options runtime \
    --identifier ai.companion.clippy \
    --sign "$codesign_identity" "$app_dir/Contents/Helpers/ClippyComputerUseRuntime"
  codesign --force $ts_flag --options runtime \
    --entitlements "$repo_root/Resources/Clippy.entitlements" \
    --sign "$codesign_identity" "$app_dir"
  codesign --verify --deep --strict "$app_dir"
  echo "signed with: $codesign_identity"
else
  echo "WARNING: signing identity not found ('$codesign_identity') — leaving ad-hoc; TCC grants will NOT persist across rebuilds." >&2
fi

echo "$app_dir"
