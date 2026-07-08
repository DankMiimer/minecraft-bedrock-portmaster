#!/bin/bash
# Launch mcpelauncher through the Weston runtime (crusty path).
# Derived from the RG34XX-SP production `_weston_launch.sh`.
#
# Usage: bash weston_launch.sh [timeout_secs] [gfxmode]   (0 = run until exit)
set -u
GAMEDIR="${GAMEDIR:?run via 'Minecraft Bedrock.sh'}"
DATA_ROOT="${MCPE_DATA_ROOT_OVERRIDE:-$GAMEDIR/profiles/default}"
DATA_DIR="${MCPE_DATA_DIR_OVERRIDE:-$DATA_ROOT/mcpelauncher}"
MCVER="${MCVER_OVERRIDE:-$(ls "$GAMEDIR/versions/" 2>/dev/null | sort -V | head -1)}"
BIN="${BIN_OVERRIDE:-$GAMEDIR/bin/mcpelauncher-client}"
EXTRA_LIB="${EXTRA_LIB:-$GAMEDIR/libs.aarch64}"
APP_EXTRA_ARGS="${APP_EXTRA_ARGS:-}"
WESTON_DIR=/tmp/weston
WESTON_SQUASH="${WESTON_SQUASH:?weston runtime path not set}"
TIMEOUT="${1:-0}"
GFX="${2:-crusty_x11egl}"
LOG="$GAMEDIR/weston_launch.log"
ESUDO="${ESUDO:-}"
CLEANED_UP=0
PERFORMANCE_ACTIVE=0
CPU_POLICY_PATHS=()
CPU_POLICY_GOVERNORS=()
CPU_POLICY_MAXFREQS=()
GPU_MIN_ORIGINAL=""

# --- Display-session detection --------------------------------------------------
# sway compositor (ROCKNIX): the game nests under sway as a wayland client;
# ES keeps running and the game window is fullscreened via the CFW helper.
# Batocera-family fbdev (Knulli H700): ES keeps /dev/fb0 and the controller
# evdev node open even while a port runs, so it must be fully stopped (not
# suspended) and restarted afterwards.
SWAY_MODE=0
SWAY_PID=""
if pidof sway >/dev/null 2>&1; then
  SWAY_MODE=1
  SWAY_PID="$(pidof sway | awk '{print $1}')"
  # When run outside the session (SSH), adopt sway's runtime env.
  if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ -z "${WAYLAND_DISPLAY:-}" ]; then
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(tr '\0' '\n' </proc/$SWAY_PID/environ 2>/dev/null | sed -n 's/^XDG_RUNTIME_DIR=//p')}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -m1 '^wayland-[0-9]*$')}"
  fi
  if [ -z "${SWAYSOCK:-}" ]; then
    SWAYSOCK="$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)"
    [ -n "$SWAYSOCK" ] && export SWAYSOCK
  fi
fi

# --- Frontend handling -----------------------------------------------------------
# Knulli/Batocera keep ES on the framebuffer/input nodes; muOS keeps its
# lightweight frontend/mux launcher around. Both must be out of the way while
# Weston/crusty owns the display.
ES_INIT=/etc/init.d/S31emulationstation
ES_WAS_RUNNING=0
MUOS_FRONTEND_STOPPED=0

is_muos() {
  local cfw_lower
  [ "${MCPE_IS_MUOS:-0}" = 1 ] && return 0
  cfw_lower="$(printf '%s' "${CFW_NAME:-}" | tr '[:upper:]' '[:lower:]')"
  case "$cfw_lower" in *muos*) return 0 ;; esac
  [ -d /opt/muos ] || [ -d /mnt/mmc/MUOS ] || [ -d /mnt/sdcard/MUOS ] ||
    [ -e /opt/muos/script/var/global/device.txt ]
}

stop_emulationstation() {
  if is_muos; then
    if pidof frontend.sh >/dev/null 2>&1 || pidof muxlaunch >/dev/null 2>&1; then
      MUOS_FRONTEND_STOPPED=1
      echo "Stopping muOS frontend..."
      $ESUDO killall -q frontend.sh muxlaunch 2>/dev/null || true
      sleep 1
    fi
    return
  fi
  [ "$SWAY_MODE" = 0 ] || return
  [ -x "$ES_INIT" ] || return
  pidof emulationstation >/dev/null 2>&1 || return
  ES_WAS_RUNNING=1
  echo "Stopping emulationstation..."
  $ESUDO "$ES_INIT" stop
}

start_emulationstation() {
  if [ "$MUOS_FRONTEND_STOPPED" = 1 ]; then
    echo "Starting muOS frontend..."
    (
      unset TMO GFX ARGS MCVER_OVERRIDE BIN_OVERRIDE EXTRA_LIB APP_EXTRA_ARGS
      unset MCPE_DATA_ROOT_OVERRIDE MCPE_DATA_DIR_OVERRIDE SDL_DRIVER_OVERRIDE
      unset GAMEWINDOW_EGLUT_CRUSTY_CONTEXT GAMEWINDOW_EGLUT_FORCE_FOCUS
      unset WESTON_SQUASH GAMEDIR MCPE_IS_MUOS
      if [ -x /opt/muos/script/mux/frontend.sh ]; then
        if command -v setsid >/dev/null 2>&1; then
          setsid /opt/muos/script/mux/frontend.sh launcher </dev/null >/dev/null 2>&1 &
        else
          /opt/muos/script/mux/frontend.sh launcher </dev/null >/dev/null 2>&1 &
        fi
      elif command -v frontend.sh >/dev/null 2>&1; then
        if command -v setsid >/dev/null 2>&1; then
          setsid frontend.sh launcher </dev/null >/dev/null 2>&1 &
        else
          frontend.sh launcher </dev/null >/dev/null 2>&1 &
        fi
      fi
    )
    MUOS_FRONTEND_STOPPED=0
    return
  fi
  [ "$ES_WAS_RUNNING" = 1 ] || return
  echo "Starting emulationstation..."
  (
    # Do not leak launcher env into the restarted ES.
    unset TMO GFX ARGS MCVER_OVERRIDE BIN_OVERRIDE EXTRA_LIB APP_EXTRA_ARGS
    unset MCPE_DATA_ROOT_OVERRIDE MCPE_DATA_DIR_OVERRIDE SDL_DRIVER_OVERRIDE
    unset GAMEWINDOW_EGLUT_CRUSTY_CONTEXT GAMEWINDOW_EGLUT_FORCE_FOCUS
    unset WESTON_SQUASH GAMEDIR
    if command -v setsid >/dev/null 2>&1; then
      setsid $ESUDO "$ES_INIT" start </dev/null >/dev/null 2>&1
    else
      $ESUDO "$ES_INIT" start </dev/null >/dev/null 2>&1
    fi
  )
  ES_WAS_RUNNING=0
}

# On sway CFWs the game is a regular window; ask the CFW helper to
# fullscreen/focus it once it appears (retries while the game boots).
sway_fullscreen_watch() {
  [ "$SWAY_MODE" = 1 ] || return
  local helper_prefix
  helper_prefix="$(printf '\160\157\162\164\155\141\163\164\145\162')"
  local sway_helper="/usr/bin/${helper_prefix}_sway_fullscreen.sh"
  [ -x "$sway_helper" ] || return
  (
    for _ in 1 2 3 4 5 6 7 8; do
      sleep 8
      "$sway_helper" mcpelauncher-client >/dev/null 2>&1
    done
  ) &
}

# Map all touchscreens onto the display the game runs on. On dual-screen
# devices (RG DS) an unmapped touch panel spans BOTH screens, so touches land
# in the wrong place. Same approach ROCKNIX itself uses for DraStic
# (for_window ... map_to_output DSI-2). The CFW's game display is the first
# entry of SDL_VIDEO_DISPLAY_PRIORITY in sway's env; fall back to the focused
# output.
sway_touch_map() {
  [ "$SWAY_MODE" = 1 ] || return
  command -v swaymsg >/dev/null 2>&1 || return
  local out=""
  [ -n "$SWAY_PID" ] &&
    out="$(tr '\0' '\n' </proc/$SWAY_PID/environ 2>/dev/null |
      sed -n 's/^SDL_VIDEO_DISPLAY_PRIORITY=//p' | cut -d, -f1)"
  if [ -z "$out" ] && command -v python3 >/dev/null 2>&1; then
    out="$(swaymsg -t get_outputs 2>/dev/null | python3 -c '
import json,sys
outs = json.load(sys.stdin)
focused = [o["name"] for o in outs if o.get("focused")]
active = [o["name"] for o in outs if o.get("active")]
print((focused or active or [""])[0])' 2>/dev/null)"
  fi
  [ -n "$out" ] || return
  echo "Mapping touchscreens to output $out"
  swaymsg "input type:touch map_to_output $out" >/dev/null 2>&1 || true
}

# --- Performance mode (generic sysfs, restored on exit) ------------------------
enable_performance_mode() {
  [ "${MCPE_PERFORMANCE_MODE:-1}" = 1 ] || return
  local policy old_governor gpu_top cpu_top old_max
  for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -r "$policy/scaling_governor" ] || continue
    old_governor="$(cat "$policy/scaling_governor")"
    CPU_POLICY_PATHS+=("$policy")
    CPU_POLICY_GOVERNORS+=("$old_governor")
    if grep -qw performance "$policy/scaling_available_governors" 2>/dev/null; then
      echo performance >"$policy/scaling_governor" 2>/dev/null || true
    fi
    # Raise the frequency ceiling to the top advertised OPP (some devices,
    # H700 included, ship with scaling_max_freq below the top step). Restored
    # on exit.
    old_max=""
    [ -r "$policy/scaling_max_freq" ] && old_max="$(cat "$policy/scaling_max_freq")"
    CPU_POLICY_MAXFREQS+=("$old_max")
    if [ -w "$policy/scaling_max_freq" ] &&
       [ -r "$policy/scaling_available_frequencies" ]; then
      cpu_top="$(awk '{ for (i = 1; i <= NF; i++) if ($i+0 > max) max = $i+0 } END { print max }' \
        "$policy/scaling_available_frequencies")"
      [ -n "$cpu_top" ] && echo "$cpu_top" >"$policy/scaling_max_freq" 2>/dev/null || true
    fi
  done
  if [ -r /sys/class/devfreq/gpu/min_freq ] &&
     [ -w /sys/class/devfreq/gpu/min_freq ] &&
     [ -r /sys/class/devfreq/gpu/available_frequencies ]; then
    GPU_MIN_ORIGINAL="$(cat /sys/class/devfreq/gpu/min_freq)"
    gpu_top="$(awk '{ for (i = 1; i <= NF; i++) if ($i > max) max = $i } END { print max }' \
      /sys/class/devfreq/gpu/available_frequencies)"
    [ -n "$gpu_top" ] && echo "$gpu_top" >/sys/class/devfreq/gpu/min_freq 2>/dev/null || true
  fi
  PERFORMANCE_ACTIVE=1
  echo "Performance mode: CPU=performance GPU-min=${gpu_top:-unchanged}"
}

restore_performance_mode() {
  [ "$PERFORMANCE_ACTIVE" = 1 ] || return
  local i policy
  for ((i = 0; i < ${#CPU_POLICY_PATHS[@]}; i++)); do
    policy="${CPU_POLICY_PATHS[$i]}"
    [ -n "${CPU_POLICY_MAXFREQS[$i]:-}" ] && [ -w "$policy/scaling_max_freq" ] &&
      echo "${CPU_POLICY_MAXFREQS[$i]}" >"$policy/scaling_max_freq" 2>/dev/null || true
    [ -w "$policy/scaling_governor" ] &&
      echo "${CPU_POLICY_GOVERNORS[$i]}" >"$policy/scaling_governor" 2>/dev/null || true
  done
  [ -n "$GPU_MIN_ORIGINAL" ] &&
    echo "$GPU_MIN_ORIGINAL" >/sys/class/devfreq/gpu/min_freq 2>/dev/null || true
  PERFORMANCE_ACTIVE=0
}

# --- Asset prewarm (page cache; removes first-use microSD stutter) -------------
prewarm_gameplay_assets() {
  [ "${MCPE_PREWARM_GAMEPLAY_ASSETS:-1}" = 1 ] || return
  local assets="$GAMEDIR/versions/$MCVER/assets"
  [ -d "$assets" ] || return
  echo "Prewarming gameplay sounds, particles, and chunk materials..."
  find "$assets" -type f \
    \( -path '*/resource_packs/vanilla/sounds/*' \
       -o -path '*/resource_packs/vanilla/particles/*' \
       -o -path '*/resource_packs/vanilla/textures/particle/*' \
       -o -path '*/renderer/materials/Particle*.material.bin' \
       -o -path '*/renderer/materials/RenderChunk*.material.bin' \) \
    -exec cat {} + >/dev/null 2>&1 || true
}

cleanup() {
  [ "$CLEANED_UP" = 0 ] || return
  CLEANED_UP=1
  "$WESTON_DIR/westonwrap.sh" cleanup 2>/dev/null || true
  $ESUDO pkill -9 -f wp_weston 2>/dev/null || true
  if [ "${FBMODE_CHANGED:-0}" = 1 ] && [ -n "${FB_ORIG_W:-}" ]; then
    fbset -xres "$FB_ORIG_W" -yres "$FB_ORIG_H" \
      -vxres "$FB_ORIG_W" -vyres $((FB_ORIG_H * 2)) 2>/dev/null || true
  fi
  restore_performance_mode
  start_emulationstation
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

case "$GFX" in
  crusty*) WRENDERER="noop";   APP_SDL_DRIVER="x11";     APP_FORCE_EGL="1" ;;
  *)       WRENDERER="pixman"; APP_SDL_DRIVER="wayland"; APP_FORCE_EGL="0" ;;
esac
APP_FORCE_EGL="${FORCE_EGL_OVERRIDE:-$APP_FORCE_EGL}"
APP_SDL_DRIVER="${SDL_DRIVER_OVERRIDE:-$APP_SDL_DRIVER}"

[ -z "$MCVER" ] && { echo "no version"; exit 1; }
[ -d "$GAMEDIR/versions/$MCVER" ] || { echo "version not found: $MCVER"; exit 1; }

stop_emulationstation
sleep 1
enable_performance_mode
prewarm_gameplay_assets
$ESUDO pkill -9 -f wp_weston 2>/dev/null
"$WESTON_DIR/westonwrap.sh" cleanup 2>/dev/null || true

# Mount the Weston runtime.
if [ ! -f "$WESTON_DIR/westonwrap.sh" ]; then
  mkdir -p "$WESTON_DIR"
  $ESUDO mount "$WESTON_SQUASH" "$WESTON_DIR" || {
    echo "Failed to mount Weston runtime: $WESTON_SQUASH"
    exit 1
  }
fi

export WP_32BIT=0
# Panel size: honour CFW-provided DISPLAY_WIDTH/HEIGHT, else probe fbset.
read -r FB_ORIG_W FB_ORIG_H < <(fbset 2>/dev/null |
  awk '/geometry/ {print $2, $3; exit}')
FB_ORIG_W="${FB_ORIG_W:-640}" FB_ORIG_H="${FB_ORIG_H:-480}"
export DISPLAY_WIDTH="${MCPE_DISPLAY_WIDTH:-${DISPLAY_WIDTH:-$FB_ORIG_W}}"
export DISPLAY_HEIGHT="${MCPE_DISPLAY_HEIGHT:-${DISPLAY_HEIGHT:-$FB_ORIG_H}}"
FBMODE_CHANGED=0
# Optional smaller-than-native mode (bigger UI + lower GPU load) on displays
# whose scaler upscales the fb (verified on Allwinner disp2). Not applicable
# under a DRM compositor (sway).
if [ "$SWAY_MODE" = 0 ] &&
   { [ "$DISPLAY_WIDTH" != "$FB_ORIG_W" ] || [ "$DISPLAY_HEIGHT" != "$FB_ORIG_H" ]; }; then
  if fbset -xres "$DISPLAY_WIDTH" -yres "$DISPLAY_HEIGHT" \
       -vxres "$DISPLAY_WIDTH" -vyres $((DISPLAY_HEIGHT * 2)) 2>/dev/null; then
    FBMODE_CHANGED=1
    echo "fb mode set to ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} (panel upscales)"
  else
    echo "fbset ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} failed; staying native"
    export DISPLAY_WIDTH="$FB_ORIG_W" DISPLAY_HEIGHT="$FB_ORIG_H"
  fi
fi
export WESTON_HEADLESS_WIDTH="$DISPLAY_WIDTH"
export WESTON_HEADLESS_HEIGHT="$DISPLAY_HEIGHT"

export XDG_DATA_HOME="$DATA_ROOT"
mkdir -p "$DATA_DIR/games/com.mojang"
# mcpelauncher hardcodes ~/.local/share/mcpelauncher in places.
mkdir -p "${HOME:-/root}/.local/share"
ln -sfn "$DATA_DIR" "${HOME:-/root}/.local/share/mcpelauncher"

$ESUDO chmod 666 /dev/fb0 /dev/mali /dev/mali0 /dev/disp 2>/dev/null
chmod +x "$BIN"
cd "$GAMEDIR"

sway_fullscreen_watch
sway_touch_map

# The client's built-in default window is 720x480; on other panels the game
# would lay its UI out for 720 wide while rendering on the real surface
# (seen as getScreenWidth=720 on a 640x480 RG35XX-H). Request the real panel
# size unless the caller passed explicit -ww/-wh.
WINDOW_SIZE_ARGS=""
case " ${APP_EXTRA_ARGS:-} " in
  *" -ww "*|*" -wh "*) ;;
  *) WINDOW_SIZE_ARGS="-ww $DISPLAY_WIDTH -wh $DISPLAY_HEIGHT" ;;
esac

echo "===== WESTON LAUNCH $(date) gfx=$GFX renderer=$WRENDERER sdl=$APP_SDL_DRIVER sway=$SWAY_MODE size=${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} ====="
TIMEOUT_CMD=()
[ "$TIMEOUT" = 0 ] || TIMEOUT_CMD=(timeout --signal=TERM "$TIMEOUT")
"${TIMEOUT_CMD[@]}" nice -n -10 env \
  WRAPPED_LIBRARY_PATH="$EXTRA_LIB:$GAMEDIR/versions/$MCVER/lib/arm64-v8a" \
  "$WESTON_DIR/westonwrap.sh" \
  headless "$WRENDERER" kiosk "$GFX" \
  env \
  SDL_VIDEODRIVER="$APP_SDL_DRIVER" \
  SDL_VIDEO_X11_FORCE_EGL="$APP_FORCE_EGL" \
  SDL_AUDIODRIVER="${MCPE_SDL_AUDIODRIVER:-openal}" \
  SDL_AUDIO_DRIVER="${MCPE_SDL_AUDIODRIVER:-openal}" \
  XDG_DATA_HOME="$DATA_ROOT" \
  MCPELAUNCHER_DATA_DIR="$DATA_DIR" \
  MALLOC_TRIM_THRESHOLD_=-1 MALLOC_MMAP_THRESHOLD_=268435456 \
  OPENSSL_armcap=0 MALLOC_CHECK_=0 \
  "$BIN" -dg "$GAMEDIR/versions/$MCVER" $WINDOW_SIZE_ARGS $APP_EXTRA_ARGS 2>&1 | tee "$LOG"
echo "--- exit: ${PIPESTATUS[0]} (124 = timeout) ---"

cleanup
