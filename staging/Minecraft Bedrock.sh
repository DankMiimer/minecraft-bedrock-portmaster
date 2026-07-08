#!/bin/bash
# Minecraft Bedrock Edition (mcpelauncher, EGLUT/Weston) — manual install.
# Target: ARM handhelds on Knulli/muOS H700, ROCKNIX/Aurknix Mali devices,
# and RK3326/R36S-class PortMaster setups via the 32-bit SDL path.
# Tested on: Anbernic RG34XX-SP (Knulli), RG DS (ROCKNIX).
#
# Place this script and the minecraftbedrock/ folder together in your ports
# directory. muOS split installs are also supported:
#   /roms/Ports/Minecraft Bedrock.sh + /ports/minecraftbedrock/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTDIR="$SCRIPT_DIR"

HOST_MACHINE="$(uname -m 2>/dev/null || echo unknown)"
case "$HOST_MACHINE" in
  aarch64|arm64|armv7l|armv8l|arm*) ;;
  *)
    echo "This port requires an ARM Linux handheld."
    exit 1
    ;;
esac

# Native 32-bit firmwares need PortMaster's armhf mod path before CFW mods are
# sourced. On 64-bit firmwares the launcher can still choose the armhf binary
# later when it is the better fit (R36S-style low-memory path).
case "$HOST_MACHINE" in
  aarch64|arm64) ;;
  *) export PORT_32BIT=Y ;;
esac

# A handheld launcher control.txt is optional for this port (the 64-bit
# EGLUT client maps pads itself), but source it when present for ESUDO,
# CFW_NAME, directory, pm_platform_helper — and get_controls, whose SDL
# mapping line the 32-bit SDL client and the LOVE menu use.
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
PM_DIR="$(printf '\120\157\162\164\115\141\163\164\145\162')"
for cf in "/opt/system/Tools/$PM_DIR" "/opt/tools/$PM_DIR" \
          "$XDG_DATA_HOME/$PM_DIR" "/userdata/system/.local/share/$PM_DIR" \
          "/storage/roms/ports/$PM_DIR" "/roms/ports/$PM_DIR" \
          "/roms/tools/$PM_DIR" "/roms2/tools/$PM_DIR" \
          "/mnt/mmc/MUOS/$PM_DIR" "/mnt/sdcard/MUOS/$PM_DIR" \
          "/mnt/mmc/ROMS/Ports/$PM_DIR" "/mnt/sdcard/ROMS/Ports/$PM_DIR"; do
  if [ -f "$cf/control.txt" ]; then
    controlfolder="$cf"
    source "$cf/control.txt" 2>/dev/null || true
    [ -f "$cf/device_info.txt" ] && source "$cf/device_info.txt" 2>/dev/null || true
    [ -n "${CFW_NAME:-}" ] && [ -f "$cf/mod_${CFW_NAME}.txt" ] &&
      source "$cf/mod_${CFW_NAME}.txt" 2>/dev/null || true
    break
  fi
done
export controlfolder="${controlfolder:-}"
export ESUDO="${ESUDO:-}"
if type get_controls >/dev/null 2>&1; then
  get_controls 2>/dev/null || true
fi
export sdl_controllerconfig="${sdl_controllerconfig:-}"

is_muos() {
  local cfw_lower
  cfw_lower="$(printf '%s' "${CFW_NAME:-}" | tr '[:upper:]' '[:lower:]')"
  case "$cfw_lower" in *muos*) return 0 ;; esac
  [ -d /opt/muos ] || [ -d /mnt/mmc/MUOS ] || [ -d /mnt/sdcard/MUOS ] ||
    [ -e /opt/muos/script/var/global/device.txt ]
}

if is_muos; then
  export MCPE_IS_MUOS=1
fi

try_game_dir() {
  [ -f "$1/run_bedrock.sh" ] && [ -f "$1/setup_apk.sh" ] &&
    { echo "$1"; return 0; }
  return 1
}

pick_game_dir() {
  local base parent pbase root
  try_game_dir "$SCRIPT_DIR/minecraftbedrock" && return
  [ -n "${directory:-}" ] && try_game_dir "/$directory/ports/minecraftbedrock" && return
  try_game_dir "/mnt/mmc/ports/minecraftbedrock" && return
  try_game_dir "/mnt/sdcard/ports/minecraftbedrock" && return
  try_game_dir "/storage/ports/minecraftbedrock" && return
  try_game_dir "/roms/ports/minecraftbedrock" && return
  try_game_dir "/userdata/roms/ports/minecraftbedrock" && return

  base="$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]')"
  parent="$(dirname "$SCRIPT_DIR")"
  pbase="$(basename "$parent" | tr '[:upper:]' '[:lower:]')"
  if [ "$base" = "ports" ] && [ "$pbase" = "roms" ]; then
    root="$(dirname "$parent")"
    try_game_dir "$root/ports/minecraftbedrock" && return
    try_game_dir "$root/Ports/minecraftbedrock" && return
  fi

  echo "$SCRIPT_DIR/minecraftbedrock"
}

GAMEDIR="$(pick_game_dir)"
export GAMEDIR

mkdir -p "$GAMEDIR/apk" "$GAMEDIR/versions" "$GAMEDIR/profiles"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
cd "$GAMEDIR"
echo "Port dir: $PORTDIR"
echo "Game dir: $GAMEDIR"
echo "CFW: ${CFW_NAME:-unknown} muOS=${MCPE_IS_MUOS:-0}"

# The Weston runtime (weston_pkg_0.2) is only needed by the 64-bit EGLUT path,
# so it is resolved lazily in run_bedrock.sh's arm64 branch — a 32-bit-only
# install on a kmsdrm device (e.g. R36S) must not fail here for a missing
# Weston it will never use.
export PM_DIR

# On-screen messaging: fbdev CFWs (Knulli) show tty1 while a port runs;
# under a DRM compositor (ROCKNIX/sway) there is no portable text surface,
# so the message goes to the log and ES returns quickly.
show_msg() {
  echo "$*"
  if ! pidof sway >/dev/null 2>&1 && [ -w /dev/tty1 ]; then
    {
      clear
      echo
      echo "  ================ MINECRAFT BEDROCK ================"
      echo
      printf '  %s\n' "$@"
      echo
      echo "  ==================================================="
    } > /dev/tty1 2>/dev/null
    sleep 6
  fi
}

import_legacy_r36s_versions() {
  [ -z "$(ls -A "$GAMEDIR/versions" 2>/dev/null)" ] || return 0
  local legacy v imported
  imported=0
  for legacy in \
    "$PORTDIR/mcpe_launcher" \
    "$(dirname "$GAMEDIR")/mcpe_launcher" \
    "/roms/ports/mcpe_launcher" \
    "/storage/roms/ports/mcpe_launcher" \
    "/roms2/ports/mcpe_launcher" \
    "/storage/roms2/ports/mcpe_launcher"
  do
    [ -d "$legacy/versions" ] || continue
    show_msg "Found legacy R36S mcpe_launcher versions." \
             "Importing them into minecraftbedrock..."
    for v in "$legacy/versions"/*; do
      [ -d "$v" ] || continue
      [ -d "$GAMEDIR/versions/$(basename "$v")" ] && continue
      cp -r "$v" "$GAMEDIR/versions/"
      imported=1
    done
    [ "$imported" = 1 ] && show_msg "Legacy versions imported."
    return 0
  done
}

import_legacy_r36s_versions

# --- First-run APK extraction -------------------------------------------------
if ls "$GAMEDIR/apk/"*.apk >/dev/null 2>&1; then
  show_msg "Found APK - extracting game files." \
           "This takes a few minutes, please wait..."
  if ! bash "$GAMEDIR/setup_apk.sh"; then
    if [ -s "$GAMEDIR/setup_error.txt" ]; then
      mapfile -t err_lines < "$GAMEDIR/setup_error.txt"
      show_msg "APK setup failed:" "${err_lines[@]}"
    else
      show_msg "APK extraction FAILED." \
               "See log.txt in the minecraftbedrock folder."
    fi
    exit 1
  fi
  show_msg "Game installed!" "Please delete the APK from the apk folder."
fi

if [ -z "$(ls -A "$GAMEDIR/versions" 2>/dev/null)" ]; then
  show_msg "No Minecraft version installed." \
           "Copy your own Bedrock APK (arm64, or arm32 for RK3326" \
           "devices like the R36S) into:" \
           "ports/minecraftbedrock/apk/" \
           "then launch this port again."
  exit 1
fi

latest_installed_version() {
  if ls "$GAMEDIR/versions" | sort -V >/dev/null 2>&1; then
    ls "$GAMEDIR/versions" | sort -V | tail -1
  else
    ls "$GAMEDIR/versions" | sort | tail -1
  fi
}

# --- In-app version selector (LOVE menu, from the R36S port) ------------------
# Shown when a version is not pinned (MCVER_OVERRIDE), the LOVE runtime exists,
# and the device has a real DRM node the menu can render on (kmsdrm). H700-class
# fbdev devices have no /dev/dri, so they fall through to newest-installed and
# rely on the separate per-version .sh entries. Disable with MCPE_MENU=0.
find_love_txt() {
  local lt
  for lt in "$controlfolder/runtimes/love_11.5/love.txt" \
            "$controlfolder/libs/love_11.5/love.txt" \
            "$controlfolder/runtimes/love/love.txt"; do
    [ -f "$lt" ] && { echo "$lt"; return 0; }
  done
  return 1
}

run_version_menu() {
  [ "${MCPE_MENU:-auto}" != 0 ] || return 1
  [ -z "${MCVER_OVERRIDE:-}" ] || return 1        # pinned entry: no menu
  [ -e /dev/dri/card0 ] || return 1               # menu renders via kmsdrm
  [ -f "$GAMEDIR/menu/main.lua" ] || return 1
  local lovetxt
  lovetxt="$(find_love_txt)" || return 1
  # shellcheck disable=SC1090
  source "$lovetxt" 2>/dev/null || return 1
  [ -n "${LOVE_RUN:-}" ] || return 1
  export MCPE_GAMEDIR="$GAMEDIR"
  : > "$GAMEDIR/menu/selected_version.txt"
  [ -n "${GPTOKEYB:-}" ] && $GPTOKEYB "love.${DEVICE_ARCH:-aarch64}" >/dev/null 2>&1 &
  SDL_AUDIODRIVER=dummy $LOVE_RUN "$GAMEDIR/menu"
  [ -n "${GPTOKEYB:-}" ] && $ESUDO kill -9 "$(pidof gptokeyb)" 2>/dev/null
  local sel
  sel="$(cat "$GAMEDIR/menu/selected_version.txt" 2>/dev/null)"
  if [ -z "$sel" ]; then
    echo "No version selected — exiting."
    exit 0
  fi
  export MCVER_OVERRIDE="$sel"
  return 0
}
run_version_menu || true

# Newest installed version wins; force one with MCVER_OVERRIDE (menu or entry).
MCVER="${MCVER_OVERRIDE:-$(latest_installed_version)}"
export MCVER_OVERRIDE="$MCVER"
export MCPE_DATA_ROOT_OVERRIDE="${MCPE_DATA_ROOT_OVERRIDE:-$GAMEDIR/profiles/default}"
mkdir -p "$MCPE_DATA_ROOT_OVERRIDE"

bash "$GAMEDIR/run_bedrock.sh"
status=$?

if command -v pm_finish >/dev/null 2>&1; then
  pm_finish || true
fi

exit "$status"
