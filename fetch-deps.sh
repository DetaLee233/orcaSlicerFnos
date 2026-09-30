#!/bin/bash
# Download the two large inputs that are intentionally NOT committed to git
# (they exceed GitHub's 100MB per-file limit). Run once before building.
set -euo pipefail
cd "$(dirname "$0")"

ORCA_URL="https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v2.4.2/OrcaSlicer_Linux_AppImage_Ubuntu2404_V2.4.2.AppImage"
ORCA_SHA="d12fb8c8eac1aecd2dfb6377acd48f994f8fa439ed5292fa532dd82880f029fd"

KASM_URL="https://github.com/kasmtech/KasmVNC/releases/download/v1.5.0/kasmvncserver_noble_1.5.0_amd64.deb"
KASM_SHA="f599fe02e2175b9817b6165f74a5d2bebdc73118dde9181ba3410963bed7ae1e"

get() {
  local url="$1" out="$2" sha="$3"
  if [ -f "$out" ] && echo "$sha  $out" | sha256sum -c - >/dev/null 2>&1; then
    echo "OK   $out (already present)"
    return
  fi
  echo "GET  $out"
  curl -fL --retry 3 -o "$out" "$url"
  echo "$sha  $out" | sha256sum -c -
}

get "$ORCA_URL" "Orca.AppImage"      "$ORCA_SHA"
get "$KASM_URL" "kasmvnc_noble.deb" "$KASM_SHA"
echo "dependencies ready"
