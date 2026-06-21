#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive_path="${1:-$repo_root/Sidekick-macOS.zip}"
output_path="${2:-$repo_root/appcast.xml}"
sparkle_version="${SPARKLE_VERSION:-2.9.3}"
release_tag="${SIDEKICK_RELEASE_TAG:-${CLIPPY_RELEASE_TAG:-${GITHUB_REF_NAME:-}}}"

if [ -z "$release_tag" ]; then
  release_tag="$(git -C "$repo_root" describe --tags --exact-match 2>/dev/null || true)"
fi
if [ -z "$release_tag" ]; then
  echo "ERROR: SIDEKICK_RELEASE_TAG or an exact git tag is required for appcast URLs." >&2
  exit 1
fi
if [ ! -f "$archive_path" ]; then
  echo "ERROR: update archive not found: $archive_path" >&2
  exit 1
fi

download_prefix="${SIDEKICK_DOWNLOAD_URL_PREFIX:-${CLIPPY_DOWNLOAD_URL_PREFIX:-https://github.com/companion-inc/sidekick/releases/download/$release_tag/}}"
product_link="${SIDEKICK_PRODUCT_LINK:-${CLIPPY_PRODUCT_LINK:-https://github.com/companion-inc/sidekick/releases/latest}}"

workdir="$(mktemp -d)"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

tools_dir="$workdir/sparkle"
updates_dir="$workdir/updates"
mkdir -p "$tools_dir" "$updates_dir"

curl -fsSL \
  "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
  -o "$tools_dir/Sparkle-$sparkle_version.tar.xz"
tar -xf "$tools_dir/Sparkle-$sparkle_version.tar.xz" -C "$tools_dir"

archive_name="$(basename "$archive_path")"
cp "$archive_path" "$updates_dir/$archive_name"
notes_name="${archive_name%.*}.md"
cat > "$updates_dir/$notes_name" <<NOTES
# Sidekick $release_tag

Desktop assistant update.
NOTES

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | \
    "$tools_dir/bin/generate_appcast" \
      --ed-key-file - \
      --download-url-prefix "$download_prefix" \
      --link "$product_link" \
      --embed-release-notes \
      -o "$workdir/appcast.xml" \
      "$updates_dir"
else
  "$tools_dir/bin/generate_appcast" \
    --download-url-prefix "$download_prefix" \
    --link "$product_link" \
    --embed-release-notes \
    -o "$workdir/appcast.xml" \
    "$updates_dir"
fi

cp "$workdir/appcast.xml" "$output_path"
echo "$output_path"
