#!/bin/bash
# MohiView for Mac - installer.
#
#   curl -fsSL https://remote.brandivolabs.com/mac.sh | bash
#
# Downloads the latest MohiView DMG for this Mac from GitHub, checks its
# SHA-256, installs it to /Applications, opens the permission settings and
# sets a random permanent password so the office can connect unattended.
set -euo pipefail

REPO="mamehedin10/mohiview"
APP="MohiView"
BASE="https://github.com/$REPO/releases/latest/download"
APP_DIR="/Applications/$APP.app"
BIN="$APP_DIR/Contents/MacOS/$APP"

say()  { printf '\n\033[1;36m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer is for macOS only."
case "$(uname -m)" in
  arm64)  ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
  *) fail "Unsupported Mac processor: $(uname -m)" ;;
esac

DMG="$APP-mac-$ARCH.dmg"
SUMS="SHA256SUMS-mac-$ARCH.txt"
TMP="$(mktemp -d)"
MNT=""
cleanup() {
  if [ -n "$MNT" ]; then hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# GitHub's download servers sometimes answer 502/503/504 for a moment: retry.
CURL_RETRY=(--retry 5 --retry-delay 3 --retry-connrefused)

say "Downloading $APP for Mac ($ARCH)..."
curl -fL "${CURL_RETRY[@]}" --progress-bar -o "$TMP/$DMG" "$BASE/$DMG" \
  || fail "Download failed. Check the internet connection and run the command again."

expected=""
if curl -fsSL "${CURL_RETRY[@]}" -o "$TMP/$SUMS" "$BASE/$SUMS"; then
  expected="$(awk -v f="$DMG" '{ n = $2; sub(/^\*/, "", n); if (n == f) print $1 }' "$TMP/$SUMS")"
fi
if [ -z "$expected" ]; then
  # Fallback: the SHA-256 that GitHub itself records for the release file.
  echo "Checksum file not available, asking GitHub's API instead..."
  if curl -fsSL "${CURL_RETRY[@]}" -o "$TMP/release.json" "https://api.github.com/repos/$REPO/releases/latest"; then
    cat > "$TMP/digest.js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  var data = $.NSData.dataWithContentsOfFile(argv[0]);
  var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
  var assets = JSON.parse(text).assets || [];
  for (var i = 0; i < assets.length; i++) {
    if (assets[i].name === argv[1] && assets[i].digest) {
      return String(assets[i].digest).replace(/^sha256:/, '');
    }
  }
  return '';
}
JS
    expected="$(osascript -l JavaScript "$TMP/digest.js" "$TMP/release.json" "$DMG" 2>/dev/null || true)"
  fi
fi
[ -n "$expected" ] || fail "Could not get the checksum from GitHub. Wait a minute and run the command again."
actual="$(shasum -a 256 "$TMP/$DMG" | awk '{ print $1 }')"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  fail "Checksum mismatch: the download is broken or tampered with. Nothing was installed."
fi
echo "Checksum OK."

say "Installing to /Applications (macOS will ask for your Mac password)..."
MNT="$(hdiutil attach -nobrowse -readonly -noautoopen "$TMP/$DMG" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"
if [ -z "$MNT" ] || [ ! -d "$MNT/$APP.app" ]; then
  fail "The disk image does not contain $APP.app."
fi
osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || true
sudo rm -rf "$APP_DIR"
sudo ditto "$MNT/$APP.app" "$APP_DIR"
sudo xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
MNT=""
echo "Installed $APP_DIR"

say "Opening $APP and the permission settings..."
open "$APP_DIR"
sleep 3
cat <<EOF

Apple requires 3 permissions, switched on by hand, once. The $APP window
shows a box with a "Configure" button for each one. Click it, then turn
ON "$APP" on the settings page that opens:

  1. Screen Recording  (if macOS asks to Quit & Reopen $APP, allow it)
  2. Accessibility     (without it the office sees the screen, but the
                        mouse and keyboard do nothing)
  3. Input Monitoring

If "$APP" is not in a list, click "+" under the list and choose
Applications > $APP. This script opens each page for you as well.

EOF
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
read -r -p "Press Enter when Screen Recording is ON for $APP... " _ < /dev/tty
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
read -r -p "Press Enter when Accessibility is ON for $APP... " _ < /dev/tty
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
read -r -p "Press Enter when Input Monitoring is ON for $APP... " _ < /dev/tty

say "Setting a permanent password for unattended access..."
PW="$(LC_ALL=C tr -dc 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789' < /dev/urandom 2>/dev/null | head -c 14 || true)"
PW_OK=0
for _ in 1 2 3 4 5; do
  res="$(sudo "$BIN" --password "$PW" 2>&1 || true)"
  case "$res" in
    *Done*) PW_OK=1; break ;;
  esac
  sleep 3
done
ID="$("$BIN" --get-id 2>/dev/null | tr -d '[:space:]' || true)"

printf '\n\033[1;32m==============================================\033[0m\n'
printf '\033[1;32m %s is ready on this Mac.\033[0m\n' "$APP"
printf '\033[1;32m ID       : %s\033[0m\n' "${ID:-open $APP to see it}"
if [ "$PW_OK" = 1 ]; then
  printf '\033[1;32m Password : %s\033[0m\n' "$PW"
  echo " Send the ID and password to the office privately (not in a group chat)."
else
  echo " The password could not be set automatically ($res)."
  echo " In $APP open Settings > Security, set a permanent password, then send"
  echo " the ID and that password to the office privately."
fi
echo " If the office sees the screen but the mouse does nothing, turn ON"
echo " $APP in System Settings > Privacy & Security > Accessibility."
printf '\033[1;32m==============================================\033[0m\n'
