#!/bin/bash
# Super Flow installer.
#
#   Install / update:  curl -fsSL https://udsy19.github.io/super-flow/install.sh | bash
#   Uninstall:         curl -fsSL https://udsy19.github.io/super-flow/install.sh | bash -s -- --uninstall
#
# Downloads the latest release from GitHub, installs it into /Applications (or ~/Applications when /Applications
# isn't writable) and opens it. Nothing else on your system is changed.
# Options (environment): SUPERFLOW_INSTALL_DIR=<folder> to install elsewhere, SUPERFLOW_NO_OPEN=1 to skip launching.
set -euo pipefail

REPO="udsy19/super-flow"
APP="Super Flow.app"
DMG_URL="https://github.com/$REPO/releases/latest/download/SuperFlow.dmg"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'
say()  { printf '%s\n' "$*"; }
step() { printf '%s→%s %s\n' "$bold" "$reset" "$*"; }
fail() { printf '%s✗ %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }

# Asks a running copy to quit and waits up to five seconds for it.
quit_running() {
  pgrep -x SuperFlow >/dev/null 2>&1 || return 0
  step "Quitting the running copy of Super Flow"
  osascript -e 'tell application id "com.udsy.superflow" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x SuperFlow >/dev/null 2>&1 || return 0; sleep 0.5; done
  fail "Super Flow is still running. Quit it from its Dock icon and run the installer again."
}

# Every installed copy, one path per line.
installed_paths() {
  for dir in "/Applications" "$HOME/Applications"; do
    [ -d "$dir/$APP" ] && printf '%s\n' "$dir/$APP"
  done
  return 0
}

[ "$(uname -s)" = "Darwin" ] || fail "Super Flow runs on macOS only."

if [ "${1:-}" = "--uninstall" ]; then
  paths="$(installed_paths)"
  [ -n "$paths" ] || fail "Super Flow isn't installed."
  quit_running
  while IFS= read -r path; do
    step "Removing $path"
    rm -rf "$path"
  done <<< "$paths"
  say "${green}✓ Super Flow was uninstalled.${reset}"
  say "${dim}Your dictation history, meetings, models and settings were kept in ~/Library/Application Support/Super Flow and${reset}"
  say "${dim}~/Library/Preferences/com.udsy.superflow.plist — delete them to remove everything.${reset}"
  exit 0
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Super Flow needs macOS 14 Sonoma or later (you have $(sw_vers -productVersion))."

say "${bold}Installing Super Flow${reset} ${dim}— voice dictation and meeting notes, all on your Mac${reset}"
tmp="$(mktemp -d -t superflow-install)"
mnt="$tmp/mount"
cleanup() { hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

step "Downloading the latest release"
curl -fL --progress-bar -o "$tmp/SuperFlow.dmg" "$DMG_URL" || fail "Download failed — check your connection and try again."

step "Verifying the disk image"
hdiutil verify "$tmp/SuperFlow.dmg" -quiet || fail "The download is damaged. Please try again."
mkdir -p "$mnt"
hdiutil attach "$tmp/SuperFlow.dmg" -nobrowse -readonly -mountpoint "$mnt" -quiet || fail "Couldn't open the disk image."
[ -d "$mnt/$APP" ] || fail "The disk image doesn't contain $APP."

dest="${SUPERFLOW_INSTALL_DIR:-/Applications}"
mkdir -p "$dest" 2>/dev/null || true
if [ ! -w "$dest" ]; then
  dest="$HOME/Applications"; mkdir -p "$dest"
fi

[ "${SUPERFLOW_NO_OPEN:-0}" = 1 ] || quit_running
step "Installing to $dest"
rm -rf "$dest/$APP"
ditto "$mnt/$APP" "$dest/$APP"
# Downloads made with curl aren't quarantined; clear the flag anyway in case the image was cached by a browser.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dest/$APP/Contents/Info.plist" 2>/dev/null || echo "")"
if [ "${SUPERFLOW_NO_OPEN:-0}" = 1 ]; then
  say "${green}✓ Super Flow ${version} is installed in $dest.${reset}"
else
  say "${green}✓ Super Flow ${version} is installed.${reset} Opening it now — look for the bar at the bottom of your screen."
  open "$dest/$APP"
fi
