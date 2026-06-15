#!/usr/bin/env bash
set -euo pipefail

repo="${CUA_DRIVER_REPO:-trycua/cua}"
version="${CUA_DRIVER_VERSION:-0.5.3}"
tag="${CUA_DRIVER_TAG:-cua-driver-rs-v$version}"
asset="${CUA_DRIVER_ASSET:-cua-driver-rs-$version-darwin-universal.tar.gz}"
dest="${1:-.build/cua-driver-release}"
base_url="https://github.com/$repo/releases/download/$tag"

rm -rf "$dest"
mkdir -p "$dest"

curl -fsSLo "$dest/$asset" "$base_url/$asset"
curl -fsSLo "$dest/checksums.txt" "$base_url/checksums.txt"

(
  cd "$dest"
  grep "  $asset$" checksums.txt | shasum -a 256 -c -
)

tar -xzf "$dest/$asset" -C "$dest"

driver="$dest/cua-driver-rs-$version-darwin-universal/cua-driver"
if [ ! -x "$driver" ]; then
  echo "ERROR: expected executable Cua driver at $driver" >&2
  exit 1
fi

"$driver" --version >&2
printf '%s\n' "$driver"
