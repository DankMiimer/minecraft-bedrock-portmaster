#!/usr/bin/env bash
# Minecraft Bedrock port — SD card preparation tool (Linux/macOS)
#
# Lays the release zip out on your SD card in the right structure for your
# CFW, and checks your APK on the PC (ABI, split-set completeness, PairIP)
# so the first on-device launch doesn't fail after minutes of extraction.
#
# Usage (interactive):  ./prepare_sd.sh
# Usage (scripted):     ./prepare_sd.sh -z minecraftbedrock-1.3.1.zip -t /media/SD -c muos -a mc.apk
set -u

ZIP="" TARGET="" CFW="" APKS=()
while getopts "z:t:c:a:h" opt; do
  case $opt in
    z) ZIP="$OPTARG" ;;
    t) TARGET="$OPTARG" ;;
    c) CFW="$OPTARG" ;;
    a) APKS+=("$OPTARG") ;;
    h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) exit 1 ;;
  esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "$*"; }

command -v unzip >/dev/null || fail "unzip is required"

# --- Gather inputs -------------------------------------------------------------
if [ -z "$ZIP" ]; then
  set -- minecraftbedrock-*.zip
  if [ $# -eq 1 ] && [ -f "$1" ]; then
    ZIP="$1"; info "Using release zip: $ZIP"
  else
    printf 'Path to the minecraftbedrock release zip: '; read -r ZIP
  fi
fi
[ -f "$ZIP" ] || fail "zip not found: $ZIP"

# Verify checksum when a SHA256SUMS.txt sits next to the zip.
SUMS="$(dirname "$ZIP")/SHA256SUMS.txt"
if [ -f "$SUMS" ]; then
  zipname="$(basename "$ZIP")"
  expected="$(grep -F "$zipname" "$SUMS" | awk '{print $1}' | head -1)"
  if [ -n "$expected" ]; then
    if command -v sha256sum >/dev/null; then
      actual="$(sha256sum "$ZIP" | awk '{print $1}')"
    else
      actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    fi
    [ "$actual" = "$expected" ] || fail "checksum mismatch for $zipname — re-download the release zip"
    info "Release zip checksum OK."
  fi
fi

if [ -z "$CFW" ]; then
  cat <<'EOF'
Which firmware does your handheld run?
  1) Knulli / Batocera   (everything goes into roms/ports/)
  2) muOS                (.sh into ROMS/Ports/, folder into ports/)
  3) ROCKNIX             (everything goes into roms/ports/)
  4) Just extract flat into the target folder
EOF
  printf 'Choice [1-4]: '; read -r c
  case "$c" in
    1) CFW=knulli ;; 2) CFW=muos ;; 3) CFW=rocknix ;; *) CFW=flat ;;
  esac
fi

if [ -z "$TARGET" ]; then
  echo "Target: the mounted SD card root (e.g. /media/$USER/SDCARD)."
  printf 'Target folder: '; read -r TARGET
fi
[ -d "$TARGET" ] || fail "target not found: $TARGET"

# --- APK validation ------------------------------------------------------------
validate_apks() {
  local has_lib=0 has_assets=0 pairip=0 abis="" f listing
  for f in "$@"; do
    [ -f "$f" ] || fail "APK not found: $f"
    listing="$(unzip -l "$f" 2>/dev/null)" || fail "corrupt or unreadable APK: $f"
    if echo "$listing" | grep -qE 'lib/[^/]+/libminecraftpe\.so'; then
      has_lib=1
      abis="$abis $(echo "$listing" | grep -oE 'lib/[^/]+/libminecraftpe\.so' | cut -d/ -f2 | sort -u | tr '\n' ' ')"
    fi
    echo "$listing" | grep -q 'libpairipcore\.so' && pairip=1
    echo "$listing" | grep -qE 'assets/(assets/)?resource_packs' && has_assets=1
  done
  [ "$pairip" = 1 ] && fail "This APK is a 1.26+ Google Play build with PairIP licensing and
cannot run outside Google Play services. Use a 1.16-1.21 APK instead
(1.16.221.01 or 1.20.x recommended)."
  if [ "$has_lib" = 0 ]; then
    if [ $# -gt 1 ] || [ "$has_assets" = 1 ]; then
      fail "No native-library APK in this set. Add split_config.arm64_v8a.apk from the same install."
    fi
    fail "This APK contains no Minecraft native libraries (libminecraftpe.so)."
  fi
  echo "$abis" | grep -qE 'arm64-v8a|armeabi-v7a' ||
    fail "APK has no ARM libraries (found:$abis). This port needs arm64-v8a (or armeabi-v7a on RK3326 devices)."
  [ "$has_assets" = 1 ] ||
    fail "No assets APK in this set. Add the install-pack split (the large one, often split_install_pack.apk)."
  info "APK OK - ABIs:$abis"
}

if [ ${#APKS[@]} -eq 0 ]; then
  printf 'Path to your Bedrock APK (Enter to skip): '; read -r a
  [ -n "$a" ] && APKS+=("$a")
fi
[ ${#APKS[@]} -gt 0 ] && validate_apks "${APKS[@]}"

# --- Layout --------------------------------------------------------------------
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
unzip -q "$ZIP" -d "$STAGING" || fail "could not extract $ZIP"
# Zips may nest everything under a single top folder — normalize.
if [ ! -d "$STAGING/minecraftbedrock" ]; then
  inner="$(find "$STAGING" -maxdepth 2 -type d -name minecraftbedrock | head -1)"
  [ -n "$inner" ] || fail "unexpected zip layout: no minecraftbedrock/ folder inside"
  STAGING="$(dirname "$inner")"
fi

case "$CFW" in
  muos)           SH_DEST="$TARGET/ROMS/Ports"; DIR_DEST="$TARGET/ports" ;;
  knulli|rocknix)
    case "$(basename "$TARGET")" in
      ports|Ports) SH_DEST="$TARGET" ;;
      *)           SH_DEST="$TARGET/roms/ports" ;;
    esac
    DIR_DEST="$SH_DEST" ;;
  *)              SH_DEST="$TARGET"; DIR_DEST="$TARGET" ;;
esac
mkdir -p "$SH_DEST" "$DIR_DEST" || fail "cannot create target directories"

for sh in "$STAGING"/*.sh; do
  [ -f "$sh" ] || continue
  cp -f "$sh" "$SH_DEST/" && info "  -> $SH_DEST/$(basename "$sh")"
done
cp -rf "$STAGING/minecraftbedrock" "$DIR_DEST/" && info "  -> $DIR_DEST/minecraftbedrock/"

if [ ${#APKS[@]} -gt 0 ]; then
  mkdir -p "$DIR_DEST/minecraftbedrock/apk"
  for f in "${APKS[@]}"; do
    cp -f "$f" "$DIR_DEST/minecraftbedrock/apk/" && info "  -> APK copied: $(basename "$f")"
  done
fi

echo
info "Done. Next steps on the device:"
info "  1. Safely eject the SD card and boot the handheld."
info "  2. Refresh the game list and launch \"Minecraft Bedrock\" from Ports."
if [ ${#APKS[@]} -gt 0 ]; then
  info "  3. First launch extracts the game (a few minutes). Delete the APK from apk/ afterwards."
else
  info "  3. Copy your Bedrock APK into ports/minecraftbedrock/apk/ first, then launch."
fi
