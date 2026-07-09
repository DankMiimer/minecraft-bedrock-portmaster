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

# The sourced PortMaster files can clobber SCRIPT_DIR (seen on Knulli:
# pick_game_dir then resolved "/minecraftbedrock"). Restore it from the
# copy taken before sourcing.
SCRIPT_DIR="$PORTDIR"

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
CONFDIR="$GAMEDIR/config"

mkdir -p "$GAMEDIR/apk" "$GAMEDIR/versions" "$GAMEDIR/profiles" "$CONFDIR"
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
# SHOW_MSG_SLEEP overrides the read pause for quick progress notes.
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
    sleep "${SHOW_MSG_SLEEP:-6}"
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

# --- Launcher menu availability ------------------------------------------------
# The LOVE menu (version picker, APK installer, settings) runs wherever
# PortMaster's love runtime is installed: nested under sway (ROCKNIX), or
# straight on the CFW's SDL video stack (Knulli/muOS fbdev-mali). If the
# runtime is missing or the menu crashes, everything falls back to the old
# auto behavior. Disable with MCPE_MENU=0; custom shortcuts that pin
# MCVER_OVERRIDE skip it too.
find_love_txt() {
  local lt
  for lt in "$controlfolder/runtimes/love_11.5/love.txt" \
            "$controlfolder/libs/love_11.5/love.txt" \
            "$controlfolder/runtimes/love/love.txt"; do
    [ -f "$lt" ] && { echo "$lt"; return 0; }
  done
  return 1
}
MENU_LOVE_TXT=""
if [ "${MCPE_MENU:-auto}" != 0 ] && [ -z "${MCVER_OVERRIDE:-}" ] &&
   [ -f "$GAMEDIR/menu/main.lua" ]; then
  MENU_LOVE_TXT="$(find_love_txt)" || MENU_LOVE_TXT=""
fi

# --- APK extraction --------------------------------------------------------------
# With the menu available, installs are user-driven from the Install screen, so
# a forgotten APK in apk/ no longer breaks every launch. Menu-less devices keep
# the old extract-on-launch behavior; a failure there is only fatal when
# nothing is installed yet.
run_apk_setup() { # [apk paths...]
  SHOW_MSG_SLEEP=1 show_msg "Found APK - extracting game files." \
                            "This takes a few minutes, please wait..."
  if bash "$GAMEDIR/setup_apk.sh" "$@"; then
    show_msg "Game installed!" "You can now delete the APK from the apk folder."
    return 0
  fi
  if [ -s "$GAMEDIR/setup_error.txt" ]; then
    mapfile -t err_lines < "$GAMEDIR/setup_error.txt"
    show_msg "APK setup failed:" "${err_lines[@]}"
  else
    show_msg "APK extraction FAILED." \
             "See log.txt in the minecraftbedrock folder."
  fi
  return 1
}

if ls "$GAMEDIR/apk/"*.apk >/dev/null 2>&1; then
  if [ -z "$(ls -A "$GAMEDIR/versions" 2>/dev/null)" ]; then
    run_apk_setup || exit 1
  elif [ -z "$MENU_LOVE_TXT" ]; then
    run_apk_setup || echo "Continuing with the already-installed versions."
  fi
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
  if sort -V </dev/null >/dev/null 2>&1; then
    ls "$GAMEDIR/versions" | sort -V | tail -1
  else
    ls "$GAMEDIR/versions" | sort | tail -1
  fi
}

# --- Frontend handling for the menu ---------------------------------------------
# Knulli ES and the muOS frontend hold the framebuffer and input nodes; they
# must be out of the way while the LOVE menu draws. Under sway (ROCKNIX) the
# menu is a normal window and nothing needs stopping. The downstream launch
# scripts stop/restart only what THEY stopped, so when the menu phase stops
# the frontend it is also the one to restore it — via the EXIT trap, which
# covers both the exit-from-menu and the after-game paths.
ES_INIT=/etc/init.d/S31emulationstation
MENU_STOPPED_ES=0
MENU_STOPPED_MUOS=0
menu_stop_frontend() {
  pidof sway >/dev/null 2>&1 && return
  if [ "${MCPE_IS_MUOS:-0}" = 1 ]; then
    if pidof frontend.sh >/dev/null 2>&1 || pidof muxlaunch >/dev/null 2>&1; then
      MENU_STOPPED_MUOS=1
      $ESUDO killall -q frontend.sh muxlaunch 2>/dev/null || true
      sleep 1
    fi
    return
  fi
  [ -x "$ES_INIT" ] || return
  pidof emulationstation >/dev/null 2>&1 || return
  MENU_STOPPED_ES=1
  $ESUDO "$ES_INIT" stop
}
menu_restore_frontend() {
  if [ "$MENU_STOPPED_MUOS" = 1 ]; then
    MENU_STOPPED_MUOS=0
    (
      unset GAMEDIR MCVER_OVERRIDE MCPE_DATA_ROOT_OVERRIDE MCPE_IS_MUOS
      if [ -x /opt/muos/script/mux/frontend.sh ]; then
        setsid /opt/muos/script/mux/frontend.sh launcher </dev/null >/dev/null 2>&1 &
      elif command -v frontend.sh >/dev/null 2>&1; then
        setsid frontend.sh launcher </dev/null >/dev/null 2>&1 &
      fi
    )
    return
  fi
  [ "$MENU_STOPPED_ES" = 1 ] || return
  MENU_STOPPED_ES=0
  (
    unset GAMEDIR MCVER_OVERRIDE MCPE_DATA_ROOT_OVERRIDE
    setsid $ESUDO "$ES_INIT" start </dev/null >/dev/null 2>&1
  )
}
trap menu_restore_frontend EXIT

# --- Launcher menu ---------------------------------------------------------------
# Loop: install/delete actions return to the menu; play/exit leave it.
MCPE_MENU_STATUS=""

valid_plain_name() { # no path tricks in names coming back from the menu
  case "$1" in ""|.|..|.*|*/*|*\\*) return 1 ;; esac
  return 0
}

menu_do_install() {
  local names=() n
  if [ -f "$CONFDIR/install_request.txt" ]; then
    while IFS= read -r n; do
      valid_plain_name "$n" && [ -f "$GAMEDIR/apk/$n" ] &&
        names+=("$GAMEDIR/apk/$n")
    done < "$CONFDIR/install_request.txt"
    rm -f "$CONFDIR/install_request.txt"
  fi
  if run_apk_setup "${names[@]}"; then
    MCPE_MENU_STATUS="Installed OK - you can delete the APK (X)"
  else
    MCPE_MENU_STATUS="Install failed - see log.txt"
  fi
}

run_launcher_menu() {
  [ -n "$MENU_LOVE_TXT" ] || return 1
  # shellcheck disable=SC1090
  source "$MENU_LOVE_TXT" 2>/dev/null || return 1
  [ -n "${LOVE_RUN:-}" ] || return 1
  export MCPE_GAMEDIR="$GAMEDIR"
  menu_stop_frontend
  local action arg love_status
  while :; do
    : > "$CONFDIR/menu_action.txt"
    export MCPE_MENU_STATUS
    [ -n "${GPTOKEYB:-}" ] && $GPTOKEYB "love.${DEVICE_ARCH:-aarch64}" >/dev/null 2>&1 &
    SDL_AUDIODRIVER=dummy \
      SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-}" \
      $LOVE_RUN "$GAMEDIR/menu"
    love_status=$?
    [ -n "${GPTOKEYB:-}" ] && $ESUDO kill -9 "$(pidof gptokeyb)" 2>/dev/null
    action="$(sed -n 1p "$CONFDIR/menu_action.txt" 2>/dev/null)"
    arg="$(sed -n 2p "$CONFDIR/menu_action.txt" 2>/dev/null)"
    case "$action" in
      play)
        valid_plain_name "$arg" && [ -d "$GAMEDIR/versions/$arg" ] &&
          export MCVER_OVERRIDE="$arg"
        return 0
        ;;
      install)
        menu_do_install
        ;;
      delete)
        if valid_plain_name "$arg" && [ -d "$GAMEDIR/versions/$arg" ]; then
          rm -rf "$GAMEDIR/versions/$arg"
          MCPE_MENU_STATUS="Deleted version $arg"
        fi
        ;;
      delete_apk)
        if valid_plain_name "$arg" && [ -f "$GAMEDIR/apk/$arg" ]; then
          rm -f "$GAMEDIR/apk/$arg"
          MCPE_MENU_STATUS="Deleted $arg"
        fi
        ;;
      backup_create)
        mkdir -p "$GAMEDIR/backups"
        bk="backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        members=(profiles)
        [ -f "$CONFDIR/settings.cfg" ] && members+=(config/settings.cfg)
        SHOW_MSG_SLEEP=1 show_msg "Creating backup..." \
                                  "(worlds, settings, profiles)"
        if tar czf "$GAMEDIR/backups/$bk.part" -C "$GAMEDIR" "${members[@]}" 2>/dev/null &&
           mv "$GAMEDIR/backups/$bk.part" "$GAMEDIR/backups/$bk"; then
          MCPE_MENU_STATUS="Backup created ($(du -h "$GAMEDIR/backups/$bk" 2>/dev/null | cut -f1))"
        else
          rm -f "$GAMEDIR/backups/$bk.part"
          MCPE_MENU_STATUS="Backup FAILED - check free space"
        fi
        ;;
      backup_restore)
        if valid_plain_name "$arg" && [ -f "$GAMEDIR/backups/$arg" ]; then
          SHOW_MSG_SLEEP=1 show_msg "Restoring backup..." "$arg"
          if tar xzf "$GAMEDIR/backups/$arg" -C "$GAMEDIR" 2>/dev/null; then
            MCPE_MENU_STATUS="Backup restored"
          else
            MCPE_MENU_STATUS="Restore FAILED - see log.txt"
          fi
        fi
        ;;
      backup_delete)
        if valid_plain_name "$arg" && [ -f "$GAMEDIR/backups/$arg" ]; then
          rm -f "$GAMEDIR/backups/$arg"
          MCPE_MENU_STATUS="Backup deleted"
        fi
        ;;
      update)
        # Self-update. The updater overwrites this very script, which is
        # safe only because this whole function was parsed before running:
        # run the updater from a copy (its own file also gets overwritten;
        # it protects itself the same way), then exit WITHOUT reading
        # anything further from this file. The EXIT trap restores the
        # frontend that the menu phase stopped.
        echo "Menu: update chosen."
        if [ -f "$GAMEDIR/update_port.sh" ]; then
          cp -f "$GAMEDIR/update_port.sh" "$GAMEDIR/.update_run.sh"
          MCPE_ENTRY_DIR="$PORTDIR" MCPE_GAMEDIR="$GAMEDIR" \
            bash "$GAMEDIR/.update_run.sh" || true
          rm -f "$GAMEDIR/.update_run.sh"
        else
          show_msg "Updater missing (update_port.sh)." \
                   "Re-install the port from the release zip."
        fi
        exit 0
        ;;
      exit)
        echo "Menu: exit chosen."
        exit 0
        ;;
      *)
        [ -s "$CONFDIR/menu_error.txt" ] &&
          { echo "menu error:"; cat "$CONFDIR/menu_error.txt"; }
        echo "Menu unavailable (love exit $love_status) - using defaults."
        return 1
        ;;
    esac
  done
}
run_launcher_menu || true

# The menu can delete versions; re-check before launching.
if [ -z "$(ls -A "$GAMEDIR/versions" 2>/dev/null)" ]; then
  show_msg "No Minecraft version installed anymore." \
           "Copy a Bedrock APK into ports/minecraftbedrock/apk/" \
           "and install it from the launcher menu."
  exit 1
fi

# --- Persisted settings (written by the menu's Settings screen) ------------------
# Only whitelisted keys are consumed and every value is validated, so a
# hand-edited settings.cfg cannot inject anything. Explicit env pins win over
# the saved settings.
SETTINGS_VERSION=""
apply_settings() {
  local f="$CONFDIR/settings.cfg" k v
  [ -f "$f" ] || return 0
  while IFS='=' read -r k v; do
    case "$k" in
      version)
        v="${v//[!A-Za-z0-9._+ -]/}"
        SETTINGS_VERSION="$v"
        continue
        ;;
    esac
    v="${v//[!A-Za-z0-9]/}"
    case "$k" in
      fps_cap)
        case "$v" in ''|0|*[!0-9]*) ;; *)
          [ -z "${MCPE_MAX_FPS:-}" ] && export MCPE_MAX_FPS="$v" ;;
        esac ;;
      render_distance) # stored in chunks; the game option is in blocks
        case "$v" in ''|0|*[!0-9]*) ;; *)
          [ -z "${MCPE_RENDER_DISTANCE:-}" ] && export MCPE_RENDER_DISTANCE="$((v * 16))" ;;
        esac ;;
      abi)
        case "$v" in arm64|armhf)
          [ -z "${MCPE_ABI_OVERRIDE:-}" ] && export MCPE_ABI_OVERRIDE="$v" ;;
        esac ;;
      ui_scale)
        case "$v" in 1|2|3)
          [ -z "${MCPE_UI_DENSITY_SCALE:-}" ] && export MCPE_UI_DENSITY_SCALE="$v" ;;
        esac ;;
      vsync)
        case "$v" in 0|1)
          [ -z "${MCPE_VSYNC:-}" ] && export MCPE_VSYNC="$v" ;;
        esac ;;
      perf_mode)
        case "$v" in 0|1)
          [ -z "${MCPE_PERFORMANCE_MODE:-}" ] && export MCPE_PERFORMANCE_MODE="$v" ;;
        esac ;;
      options_tuning)
        case "$v" in 0|1)
          [ -z "${MCPE_PERFORMANCE_OPTIONS:-}" ] && export MCPE_PERFORMANCE_OPTIONS="$v" ;;
        esac ;;
      measure_fps)
        case "$v" in 0|1)
          [ -z "${MCPE_MEASURE_FPS:-}" ] && export MCPE_MEASURE_FPS="$v" ;;
        esac ;;
    esac
  done < "$f"
}
apply_settings

# 1.16 predates RenderDragon and OreUI, and older clients cannot open newer
# worlds. With the single launcher entry, keep the old dedicated-entry safety
# by automatically isolating any selected 1.16 build in its own profile.
is_116_version() {
  case "$1" in 1.16*) return 0 ;; *) return 1 ;; esac
}

set_seed_option() {
  local options_file="$1" key="$2" value="$3"
  if grep -q "^${key}:" "$options_file" 2>/dev/null; then
    sed -i "s#^${key}:.*#${key}:${value}#" "$options_file"
  else
    echo "${key}:${value}" >>"$options_file"
  fi
}

seed_116_options() {
  local options_file default_options
  options_file="$MCPE_DATA_ROOT_OVERRIDE/mcpelauncher/games/com.mojang/minecraftpe/options.txt"
  [ ! -f "$options_file" ] || return

  mkdir -p "$(dirname "$options_file")"
  default_options="$GAMEDIR/profiles/default/mcpelauncher/games/com.mojang/minecraftpe/options.txt"
  if [ -f "$default_options" ]; then
    cp "$default_options" "$options_file"
  else
    : >"$options_file"
  fi

  set_seed_option "$options_file" gfx_vsync 0
  set_seed_option "$options_file" gfx_msaa 1
  set_seed_option "$options_file" gfx_fancyskies 0
  set_seed_option "$options_file" gfx_toggleclouds 0
  set_seed_option "$options_file" gfx_smoothlighting 0
  set_seed_option "$options_file" gfx_transparentleaves 0
}

# Version precedence: custom/menu pin > remembered menu selection > newest.
MCVER="${MCVER_OVERRIDE:-}"
if [ -z "$MCVER" ] && [ -n "$SETTINGS_VERSION" ] &&
   [ -d "$GAMEDIR/versions/$SETTINGS_VERSION" ]; then
  MCVER="$SETTINGS_VERSION"
fi
MCVER="${MCVER:-$(latest_installed_version)}"
export MCVER_OVERRIDE="$MCVER"
if [ -z "${MCPE_DATA_ROOT_OVERRIDE:-}" ] && is_116_version "$MCVER"; then
  export MCPE_DATA_ROOT_OVERRIDE="$GAMEDIR/profiles/$MCVER"
  export MCPE_RENDER_DISTANCE="${MCPE_RENDER_DISTANCE:-64}"
  export MCPE_MAX_FPS="${MCPE_MAX_FPS:-40}"
  seed_116_options
else
  export MCPE_DATA_ROOT_OVERRIDE="${MCPE_DATA_ROOT_OVERRIDE:-$GAMEDIR/profiles/default}"
fi
mkdir -p "$MCPE_DATA_ROOT_OVERRIDE"

bash "$GAMEDIR/run_bedrock.sh"
status=$?

if command -v pm_finish >/dev/null 2>&1; then
  pm_finish || true
fi

exit "$status"
