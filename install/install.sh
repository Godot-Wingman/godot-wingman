#!/bin/sh
# Installs Godot Pilot on macOS or Linux and adds it to the AI apps on this computer.
#
#   curl -fsSL https://raw.githubusercontent.com/Albis0/godot-pilot/main/install/install.sh | sh
#
# What it does:
# 1. Downloads the executable for this computer from the newest GitHub release.
# 2. Checks it against the release's SHA256SUMS file.
# 3. Puts it in ~/.local/bin/godot-pilot.
# 4. Runs "godot-pilot setup", which adds Godot Pilot to Codex, Claude, Cursor... (a copy
#    of every changed settings file is kept next to it).
#
# A file downloaded with curl is not quarantined, so macOS does not block it.
#
# Options (environment variables):
#   GODOT_PILOT_INSTALL_DIR   install somewhere else
#   GODOT_PILOT_NO_SETUP=1    only download; do not change AI app settings
#   GITHUB_TOKEN              GitHub token, needed only while the repository is private
set -eu

repository="Albis0/godot-pilot"
install_folder="${GODOT_PILOT_INSTALL_DIR:-$HOME/.local/bin}"
executable_path="$install_folder/godot-pilot"

case "$(uname -s)" in
  Darwin) platform_name="macos" ;;
  Linux) platform_name="linux" ;;
  *) echo "This script is for macOS and Linux. On Windows use install.ps1." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) architecture_name="arm64" ;;
  x86_64 | amd64) architecture_name="x64" ;;
  *) echo "Unsupported processor: $(uname -m)" >&2; exit 1 ;;
esac
asset_name="godot-pilot-$platform_name-$architecture_name"

github() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "User-Agent: godot-pilot-installer" -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
  else
    curl -fsSL -H "User-Agent: godot-pilot-installer" "$@"
  fi
}

# The API URL of the asset with this name in the newest release that is not a draft.
# The releases list is newest first; only the first release's assets are read.
find_asset_url() {
  github -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$repository/releases?per_page=1" |
    tr ',' '\n' |
    awk -v wanted="\"name\": \"$1\"" '
      /"url": "https:\/\/api.github.com\/repos\/.*\/releases\/assets\// { url = $0 }
      index($0, wanted) { sub(/.*"url": "/, "", url); sub(/".*/, "", url); print url; exit }
    '
}

echo "Looking for the newest Godot Pilot release..."
executable_url="$(find_asset_url "$asset_name")"
checksums_url="$(find_asset_url "SHA256SUMS")"
if [ -z "$executable_url" ] || [ -z "$checksums_url" ]; then
  echo "The newest release has no $asset_name or SHA256SUMS file." >&2
  exit 1
fi

mkdir -p "$install_folder"
download_path="$executable_path.download"
echo "Downloading $asset_name..."
github -H "Accept: application/octet-stream" "$executable_url" -o "$download_path"
expected_checksum="$(github -H "Accept: application/octet-stream" "$checksums_url" | awk -v wanted="$asset_name" '$2 == wanted || $2 == "*" wanted { print $1 }')"
if command -v sha256sum > /dev/null 2>&1; then
  actual_checksum="$(sha256sum "$download_path" | awk '{ print $1 }')"
else
  actual_checksum="$(shasum -a 256 "$download_path" | awk '{ print $1 }')"
fi
if [ -z "$expected_checksum" ] || [ "$actual_checksum" != "$expected_checksum" ]; then
  rm -f "$download_path"
  echo "The download does not match its SHA-256 checksum, so it was not installed. Try again later." >&2
  exit 1
fi

chmod +x "$download_path"
mv -f "$download_path" "$executable_path"
echo "Installed $executable_path"

case ":$PATH:" in
  *":$install_folder:"*) ;;
  *) echo "Note: $install_folder is not in your PATH. Add it to run godot-pilot from a terminal." ;;
esac

if [ "${GODOT_PILOT_NO_SETUP:-}" = "1" ]; then
  exit 0
fi
"$executable_path" setup
