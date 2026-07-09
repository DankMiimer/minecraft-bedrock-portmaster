#!/bin/bash
# Extract a user-supplied Minecraft Bedrock APK into versions/.
# Supports a single full APK, or Google Play split APKs (base + lib +
# install-pack) placed together in $GAMEDIR/apk/.
# Dual-ABI: extracts arm64-v8a (64-bit EGLUT client) and/or armeabi-v7a
# (32-bit kmsdrm client) — whichever the APK carries. Universal APKs give a
# version that can run on both clients.
#
# Usage: setup_apk.sh [apk file...]
# With arguments (the launcher menu's Install screen passes them) only those
# files are processed; without, every .apk in $GAMEDIR/apk/ is treated as one
# install set.
set -u
GAMEDIR="${GAMEDIR:?run via 'Minecraft Bedrock.sh'}"
APKDIR="$GAMEDIR/apk"

msg() { echo "[setup] $*"; }

# Failure reason is also written to setup_error.txt so the launch script can
# show it on the device screen instead of a generic "see log.txt".
fail() {
  msg "ERROR: $*"
  printf '%s\n' "$@" > "$GAMEDIR/setup_error.txt" 2>/dev/null
  exit 1
}
rm -f "$GAMEDIR/setup_error.txt" 2>/dev/null

if [ $# -gt 0 ]; then
  APKS=("$@")
else
  shopt -s nullglob
  APKS=("$APKDIR"/*.apk)
  shopt -u nullglob
fi
[ ${#APKS[@]} -gt 0 ] || fail "no APK files found in $APKDIR"

for apk in "${APKS[@]}"; do
  unzip -t "$apk" >/dev/null 2>&1 ||
    fail "corrupt or incomplete APK: $(basename "$apk")" \
         "Re-download / re-copy it and try again."
done

# Classify the provided APKs.
FULL_APK="" BASE_APK="" LIB_APK="" PACK_APK=""
for apk in "${APKS[@]}"; do
  has_lib=0 has_assets=0
  unzip -l "$apk" | grep -qE "lib/(arm64-v8a|armeabi-v7a)/libminecraftpe.so" && has_lib=1
  unzip -l "$apk" | grep -q "assets/" && has_assets=1
  if [ $has_lib = 1 ] && [ $has_assets = 1 ]; then
    FULL_APK="$apk"
  elif [ $has_lib = 1 ]; then
    LIB_APK="$apk"
  elif unzip -l "$apk" | grep -qE "assets/(assets/)?resource_packs"; then
    PACK_APK="$apk"
  else
    BASE_APK="$apk"
  fi
done

if [ -z "$FULL_APK" ] && [ -z "$LIB_APK" ]; then
  # Tell the user exactly what they gave us instead of a generic failure.
  found_abis="$(for apk in "${APKS[@]}"; do
    unzip -l "$apk" 2>/dev/null | grep -oE 'lib/[^/]+/' | sed 's#lib/##;s#/##'
  done | sort -u | tr '\n' ' ')"
  if [ -n "$found_abis" ]; then
    fail "APK contains no ARM Minecraft libraries." \
         "ABIs found: $found_abis" \
         "This port needs arm64-v8a (or armeabi-v7a on RK3326 devices)."
  elif [ -n "$BASE_APK" ] || [ -n "$PACK_APK" ]; then
    fail "Split APK set is missing the native-library APK." \
         "Copy split_config.arm64_v8a.apk (from the same install)" \
         "into the apk/ folder together with the other parts."
  else
    fail "no APK containing lib/<abi>/libminecraftpe.so found" \
         "Provide a full Bedrock APK or the complete split set" \
         "(base + split_config.arm64_v8a + install-pack)."
  fi
fi

# 1.26+ Google Play builds carry PairIP licensing (libpairipcore.so) and
# refuse to run outside Play services — reject up front with a clear reason
# instead of extracting for minutes and crashing at first launch.
for apk in "${FULL_APK:-}" "${LIB_APK:-}" "${BASE_APK:-}"; do
  [ -n "$apk" ] || continue
  if unzip -l "$apk" 2>/dev/null | grep -q "libpairipcore\.so"; then
    fail "This APK is a 1.26+ Google Play build with PairIP licensing." \
         "These cannot run outside Google Play services." \
         "Use a 1.16-1.21 APK instead (1.16.221.01 or 1.20.x recommended)."
  fi
done

# Version name = APK filename (matching the original R36S port convention).
SRC="${FULL_APK:-$LIB_APK}"
MCVER="$(basename "$SRC" .apk)"
VERDIR="$GAMEDIR/versions/$MCVER"
[ -d "$VERDIR" ] && fail "version '$MCVER' already exists — rename the APK or remove the old version"

LIB_SRC="${FULL_APK:-$LIB_APK}"
GOT_ABI=""
extract_abi() {
  local abi="$1"
  unzip -l "$LIB_SRC" | grep -q "lib/$abi/libminecraftpe.so" || return 0
  mkdir -p "$VERDIR/lib/$abi"
  unzip -j -q -o "$LIB_SRC" "lib/$abi/*.so" -d "$VERDIR/lib/$abi/" ||
    fail "$abi library extraction failed"
  # FMOD is dlopen'd under a versioned name.
  [ -f "$VERDIR/lib/$abi/libfmod.so" ] &&
    cp "$VERDIR/lib/$abi/libfmod.so" "$VERDIR/lib/$abi/libfmod.so.12.0"
  GOT_ABI="$GOT_ABI $abi"
}

msg "Extracting '$MCVER' (this can take a few minutes)..."
extract_abi arm64-v8a
extract_abi armeabi-v7a
[ -n "$GOT_ABI" ] || fail "no usable ABI found in $LIB_SRC"

# The R36S armhf launcher expects bionic shim libc/libm to be visible beside
# the extracted Android game libraries. The original working R36S port copied
# them into every version directory; keep that behavior for compatibility.
if [ -d "$VERDIR/lib/armeabi-v7a" ]; then
  for shim in libc.so libm.so; do
    for src in "$GAMEDIR/bin32/lib/armeabi-v7a/$shim" \
               "$GAMEDIR/lib32/armeabi-v7a/$shim"; do
      if [ -f "$src" ]; then
        cp -f "$src" "$VERDIR/lib/armeabi-v7a/$shim"
        break
      fi
    done
  done
fi

if [ -n "$FULL_APK" ]; then
  unzip -q -o "$FULL_APK" "assets/*" -d "$VERDIR/" || fail "asset extraction failed"
else
  [ -n "$PACK_APK" ] ||
    fail "Split APK set is missing the assets APK." \
         "Copy the install-pack split (the large one with resource_packs," \
         "often split_install_pack.apk) into apk/ with the other parts."
  unzip -q -o "$PACK_APK" "assets/*" -d "$VERDIR/" || fail "asset extraction failed"
  [ -n "$BASE_APK" ] &&
    unzip -q -o "$BASE_APK" "AndroidManifest.xml" -d "$VERDIR/" 2>/dev/null
fi

# IMPORTANT: 1.20.51+ Play install packs use a nested assets/assets/ layout
# on purpose. Do NOT flatten it — the game aborts with
# "Unable to locate asset: bootstrap.json" if flattened.

msg "SUCCESS: installed version '$MCVER' (ABIs:$GOT_ABI)"
msg "Assets: $(du -sh "$VERDIR/assets" 2>/dev/null | cut -f1)"
msg "Please DELETE the APK files from $APKDIR now."
