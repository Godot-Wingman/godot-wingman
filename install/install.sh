#!/bin/sh
# Installs Godot Wingman on macOS or Linux and adds it to the AI apps on this computer.
#
#   curl -fsSL https://raw.githubusercontent.com/Albis0/godot-wingman/main/install/install.sh | sh
#
# What it does:
# 1. Looks for Bun (https://bun.sh). When it is missing, installs it with Bun's own
#    installer. With Bun, Godot Wingman is one small file (godot-wingman.js, about 1-2 MB).
#    When Bun cannot be used, it downloads the single-file program instead (about 100 MB,
#    with Bun built in).
# 2. Checks the download against the release's SHA256SUMS file.
# 3. Puts it in ~/.local/bin (godot-wingman, plus godot-wingman.js when Bun runs it).
# 4. Runs "godot-wingman setup", which adds Godot Wingman to Codex, Claude, Cursor... (a copy
#    of every changed settings file is kept next to it).
#
# A file downloaded with curl is not quarantined, so macOS does not block it.
#
# Options (environment variables):
#   GODOT_WINGMAN_INSTALL_DIR        install somewhere else
#   GODOT_WINGMAN_USE_EXECUTABLE=1   always use the single-file program; never install Bun
#   GODOT_WINGMAN_NO_SETUP=1         only download; do not change AI app settings
#   GITHUB_TOKEN                     GitHub token, needed only while the repository is private
set -eu

repository="Albis0/godot-wingman"
install_folder="${GODOT_WINGMAN_INSTALL_DIR:-$HOME/.local/bin}"
launcher_path="$install_folder/godot-wingman"
bundle_name="godot-wingman.js"
bundle_path="$install_folder/$bundle_name"
# The bundle is built and tested with this Bun version or newer.
minimum_bun_major=1
minimum_bun_minor=3

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
executable_name="godot-wingman-$platform_name-$architecture_name"

github() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL -H "User-Agent: godot-wingman-installer" -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
  else
    curl -fsSL -H "User-Agent: godot-wingman-installer" "$@"
  fi
}

# The API URL of the asset with this name in the newest release that is not a draft.
# Works with compact and indented JSON: one value per line, spaces around ":" removed.
find_asset_url() {
  printf '%s\n' "$release_json" |
    tr ',{}' '\n\n\n' |
    sed -e 's/^[[:space:]]*//' -e 's/"[[:space:]]*:[[:space:]]*"/":"/' |
    awk -v wanted="\"name\":\"$1\"" '
      /^"url":"https:\/\/api\.github\.com\/repos\/.*\/releases\/assets\// { url = $0 }
      $0 == wanted { sub(/^"url":"/, "", url); sub(/".*/, "", url); print url; exit }
    '
}

# The full path of a Bun that is new enough, or nothing.
find_bun() {
  for candidate in "$(command -v bun 2>/dev/null || true)" "$HOME/.bun/bin/bun"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] || continue
    version="$("$candidate" --version 2>/dev/null || true)"
    major="$(printf '%s' "$version" | cut -d. -f1)"
    minor="$(printf '%s' "$version" | cut -d. -f2)"
    case "$major$minor" in *[!0-9]* | "") continue ;; esac
    if [ "$major" -gt "$minimum_bun_major" ] ||
      { [ "$major" -eq "$minimum_bun_major" ] && [ "$minor" -ge "$minimum_bun_minor" ]; }; then
      printf '%s\n' "$candidate"
      return
    fi
    echo "Bun $version is older than $minimum_bun_major.$minimum_bun_minor." >&2
  done
  return 0
}

# Downloads a release file to a path and checks it against SHA256SUMS.
save_checked_asset() {
  asset_name="$1"
  target_path="$2"
  asset_url="$(find_asset_url "$asset_name")"
  if [ -z "$asset_url" ]; then
    echo "The newest release has no $asset_name file." >&2
    exit 1
  fi
  download_path="$target_path.download"
  github -H "Accept: application/octet-stream" "$asset_url" -o "$download_path"
  expected_checksum="$(printf '%s\n' "$checksums" | awk -v wanted="$asset_name" '$2 == wanted || $2 == "*" wanted { print $1 }')"
  if command -v sha256sum > /dev/null 2>&1; then
    actual_checksum="$(sha256sum "$download_path" | awk '{ print $1 }')"
  else
    actual_checksum="$(shasum -a 256 "$download_path" | awk '{ print $1 }')"
  fi
  if [ -z "$expected_checksum" ] || [ "$actual_checksum" != "$expected_checksum" ]; then
    rm -f "$download_path"
    echo "The download of $asset_name does not match its SHA-256 checksum, so it was not installed. Try again later." >&2
    exit 1
  fi
  mv -f "$download_path" "$target_path"
}

echo "Looking for the newest Godot Wingman release..."
release_json="$(github -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$repository/releases?per_page=1")"
checksums_url="$(find_asset_url "SHA256SUMS")"
if [ -z "$checksums_url" ]; then
  echo "The newest release has no SHA256SUMS file." >&2
  exit 1
fi
checksums="$(github -H "Accept: application/octet-stream" "$checksums_url")"
mkdir -p "$install_folder"

bun_path=""
if [ "${GODOT_WINGMAN_USE_EXECUTABLE:-}" != "1" ] && [ -n "$(find_asset_url "$bundle_name")" ]; then
  bun_path="$(find_bun)"
  if [ -z "$bun_path" ]; then
    echo "Installing Bun (https://bun.sh), which runs Godot Wingman..."
    curl -fsSL https://bun.sh/install | bash || echo "Bun could not be installed." >&2
    bun_path="$(find_bun)"
  fi
fi

if [ -n "$bun_path" ]; then
  echo "Downloading the small version of Godot Wingman for Bun..."
  save_checked_asset "$bundle_name" "$bundle_path"
  # Replaces an executable from an earlier install with a small launcher.
  rm -f "$launcher_path"
  printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$bun_path" "$bundle_path" > "$launcher_path"
  chmod +x "$launcher_path"
  echo "Installed $bundle_path (run by $bun_path)"
  set -- "$bun_path" "$bundle_path"
else
  echo "Downloading Godot Wingman (single-file program, about 100 MB)..."
  save_checked_asset "$executable_name" "$launcher_path.new"
  chmod +x "$launcher_path.new"
  mv -f "$launcher_path.new" "$launcher_path"
  rm -f "$bundle_path"
  echo "Installed $launcher_path"
  set -- "$launcher_path"
fi

case ":$PATH:" in
  *":$install_folder:"*) ;;
  *) echo "Note: $install_folder is not in your PATH. Add it to run godot-wingman from a terminal." ;;
esac

if [ "${GODOT_WINGMAN_NO_SETUP:-}" = "1" ]; then
  exit 0
fi
"$@" setup
