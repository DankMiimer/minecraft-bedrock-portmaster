#!/bin/bash
# Launch the 32-bit (armhf) mcpelauncher client directly on KMS/DRM.
# This is the R36S-class path (RK3326/RK3566 with a real /dev/dri): the armhf
# client statically links SDL3 with a kmsdrm driver, so no Weston/crusty stack
# is needed. Launch recipe from ImpressiveStay's R36S mcpe_launcher port
# (network jail removed there = working LAN), merged with this port's
# profile layout, performance mode, and asset prewarm.
set -u
GAMEDIR="${GAMEDIR:?run via 'Minecraft Bedrock.sh'}"
MCVER="${MCVER_OVERRIDE:?no version selected}"
DATA_ROOT="${MCPE_DATA_ROOT_OVERRIDE:-$GAMEDIR/profiles/default}"
DATA_DIR="$DATA_ROOT/mcpelauncher"
BIN="$GAMEDIR/bin32/mcpelauncher-client"
LOG="$GAMEDIR/weston_launch.log"
ESUDO="${ESUDO:-}"

[ -f "$GAMEDIR/versions/$MCVER/lib/armeabi-v7a/libminecraftpe.so" ] || {
  echo "version $MCVER has no 32-bit (armeabi-v7a) libraries"
  exit 1
}

# --- Frontend handling (mirrors weston_launch.sh) ----------------------------
# ROCKNIX-family launches ports with the display released, nothing to stop.
# Batocera-family (Knulli) ES and the muOS frontend hold fb/input nodes.
ES_INIT=/etc/init.d/S31emulationstation
ES_WAS_RUNNING=0
MUOS_FRONTEND_STOPPED=0
is_muos() {
  local cfw_lower
  [ "${MCPE_IS_MUOS:-0}" = 1 ] && return 0
  cfw_lower="$(printf '%s' "${CFW_NAME:-}" | tr '[:upper:]' '[:lower:]')"
  case "$cfw_lower" in *muos*) return 0 ;; esac
  [ -d /opt/muos ] || [ -d /mnt/mmc/MUOS ] || [ -d /mnt/sdcard/MUOS ]
}
stop_frontend() {
  if is_muos; then
    if pidof frontend.sh >/dev/null 2>&1 || pidof muxlaunch >/dev/null 2>&1; then
      MUOS_FRONTEND_STOPPED=1
      $ESUDO killall -q frontend.sh muxlaunch 2>/dev/null || true
      sleep 1
    fi
    return
  fi
  pidof sway >/dev/null 2>&1 && return
  [ -x "$ES_INIT" ] || return
  pidof emulationstation >/dev/null 2>&1 || return
  ES_WAS_RUNNING=1
  $ESUDO "$ES_INIT" stop
}
start_frontend() {
  if [ "$MUOS_FRONTEND_STOPPED" = 1 ]; then
    if [ -x /opt/muos/script/mux/frontend.sh ]; then
      setsid /opt/muos/script/mux/frontend.sh launcher </dev/null >/dev/null 2>&1 &
    fi
    MUOS_FRONTEND_STOPPED=0
    return
  fi
  [ "$ES_WAS_RUNNING" = 1 ] || return
  setsid $ESUDO "$ES_INIT" start </dev/null >/dev/null 2>&1
  ES_WAS_RUNNING=0
}

# --- Performance mode (restored on exit) --------------------------------------
CPU_POLICY_PATHS=()
CPU_POLICY_GOVERNORS=()
GPU_DEVFREQ_PATHS=()
GPU_DEVFREQ_GOVERNORS=()
PERFORMANCE_ACTIVE=0
enable_performance_mode() {
  [ "${MCPE_PERFORMANCE_MODE:-1}" = 1 ] || return
  local policy devfreq old_governor
  for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -r "$policy/scaling_governor" ] || continue
    old_governor="$(cat "$policy/scaling_governor")"
    CPU_POLICY_PATHS+=("$policy")
    CPU_POLICY_GOVERNORS+=("$old_governor")
    if grep -qw performance "$policy/scaling_available_governors" 2>/dev/null; then
      echo performance >"$policy/scaling_governor" 2>/dev/null || true
    fi
  done
  for devfreq in /sys/class/devfreq/*gpu*; do
    [ -r "$devfreq/governor" ] || continue
    old_governor="$(cat "$devfreq/governor")"
    GPU_DEVFREQ_PATHS+=("$devfreq")
    GPU_DEVFREQ_GOVERNORS+=("$old_governor")
    [ -w "$devfreq/governor" ] &&
      echo performance >"$devfreq/governor" 2>/dev/null || true
  done
  PERFORMANCE_ACTIVE=1
}
restore_performance_mode() {
  [ "$PERFORMANCE_ACTIVE" = 1 ] || return
  local i
  for ((i = 0; i < ${#CPU_POLICY_PATHS[@]}; i++)); do
    [ -w "${CPU_POLICY_PATHS[$i]}/scaling_governor" ] &&
      echo "${CPU_POLICY_GOVERNORS[$i]}" >"${CPU_POLICY_PATHS[$i]}/scaling_governor" 2>/dev/null || true
  done
  for ((i = 0; i < ${#GPU_DEVFREQ_PATHS[@]}; i++)); do
    [ -w "${GPU_DEVFREQ_PATHS[$i]}/governor" ] &&
      echo "${GPU_DEVFREQ_GOVERNORS[$i]}" >"${GPU_DEVFREQ_PATHS[$i]}/governor" 2>/dev/null || true
  done
  PERFORMANCE_ACTIVE=0
}

cleanup() {
  restore_performance_mode
  start_frontend
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Asset prewarm (page cache; removes first-use microSD stutter) ------------
if [ "${MCPE_PREWARM_GAMEPLAY_ASSETS:-1}" = 1 ] && [ -d "$GAMEDIR/versions/$MCVER/assets" ]; then
  find "$GAMEDIR/versions/$MCVER/assets" -type f \
    \( -path '*/resource_packs/vanilla/sounds/*' \
       -o -path '*/resource_packs/vanilla/particles/*' \) \
    -exec cat {} + >/dev/null 2>&1 || true
fi

stop_frontend
enable_performance_mode

# --- Environment (ImpressiveStay's working RK3326 recipe) ---------------------
export OPENSSL_armcap=0
export MALLOC_CHECK_=0
# Mesa knobs are inert on closed-blob devices, needed on Panfrost ones.
export MESA_GL_VERSION_OVERRIDE=2.0
export MESA_GLES_VERSION_OVERRIDE=2.0
export LIBGL_ES=2
export vblank_mode=0
export SDL_RENDER_VSYNC=0
export SDL_VIDEO_KMSDRM_DOUBLE_BUFFER=1
export MESA_GLSL_CACHE_DISABLE=0
export MESA_GLSL_CACHE_DIR="$GAMEDIR/.mesa_cache"
mkdir -p "$GAMEDIR/.mesa_cache"
export PAN_MESA_DEBUG=noaff,deqp
# 32-bit path targets <=1GB devices: give memory back to the OS aggressively.
export MALLOC_MMAP_THRESHOLD_=131072
export MALLOC_TRIM_THRESHOLD_=131072
export SDL_JOYSTICK_HIDAPI=0
export SDL_JOYSTICK_DEADZONE=12000
export SDL_AUDIODRIVER="${MCPE_SDL_AUDIODRIVER:-alsa}"

# Display driver, per stack:
#  - sway compositor (ROCKNIX/Aurknix): the client renders as a Wayland
#    surface; sway owns /dev/dri, so kmsdrm would fail to get DRM master.
#  - otherwise (DarkOS RE and ArkOS-family: ES on fbdev/kmsdrm): the client
#    takes over kmsdrm directly.
SWAY_MODE=0
if [ "${MCPE_SDL_VIDEODRIVER:-}" = wayland ] || pidof sway >/dev/null 2>&1; then
  SWAY_MODE=1
fi
if [ -n "${MCPE_SDL_VIDEODRIVER:-}" ]; then
  export SDL_VIDEODRIVER="$MCPE_SDL_VIDEODRIVER"
elif [ "$SWAY_MODE" = 1 ]; then
  export SDL_VIDEODRIVER=wayland
else
  export SDL_VIDEODRIVER=kmsdrm
fi

if [ "$SDL_VIDEODRIVER" = kmsdrm ]; then
  export SDL_VIDEO_KMSDRM_CARD_INDEX=0
  export XDG_RUNTIME_DIR=/tmp/kmsdrm_runtime
  $ESUDO mkdir -p /tmp/kmsdrm_runtime
  $ESUDO chmod 700 /tmp/kmsdrm_runtime
  $ESUDO chmod 666 /dev/dri/card0 /dev/dri/renderD128 /dev/tty0 /dev/tty1 2>/dev/null
else
  # Wayland: adopt sway's runtime env when launched outside the session (SSH).
  SWAY_PID="$(pidof sway 2>/dev/null | awk '{print $1}')"
  if [ -n "$SWAY_PID" ]; then
    [ -z "${XDG_RUNTIME_DIR:-}" ] &&
      export XDG_RUNTIME_DIR="$(tr '\0' '\n' </proc/$SWAY_PID/environ 2>/dev/null | sed -n 's/^XDG_RUNTIME_DIR=//p')"
    [ -z "${WAYLAND_DISPLAY:-}" ] &&
      export WAYLAND_DISPLAY="$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -m1 '^wayland-[0-9]*$')"
    if [ -z "${SWAYSOCK:-}" ]; then
      SWAYSOCK="$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)"
      [ -n "$SWAYSOCK" ] && export SWAYSOCK
    fi
  fi
fi

# Controller: the armhf client is an SDL app and honours the CFW's SDL mapping
# line, exported by the entry script from get_controls.
[ -n "${sdl_controllerconfig:-}" ] && export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

export LD_LIBRARY_PATH="$GAMEDIR/versions/$MCVER/lib/armeabi-v7a:$GAMEDIR/versions/$MCVER/lib/native/armeabi-v7a:$GAMEDIR/bin32/lib/armeabi-v7a:$GAMEDIR/lib32/armeabi-v7a:$GAMEDIR/lib32/armhf-system:/usr/lib/arm-linux-gnueabihf:/lib/arm-linux-gnueabihf:/usr/lib32:/lib32:/usr/lib:/lib"

# Data layout: same profile scheme as the 64-bit path, so a version's worlds
# and settings are identical regardless of which client ran it.
export XDG_DATA_HOME="$DATA_ROOT"
export MCPELAUNCHER_DATA_DIR="$DATA_DIR"
mkdir -p "$DATA_DIR/games/com.mojang"
# mcpelauncher hardcodes ~/.local/share/mcpelauncher in places.
mkdir -p "${HOME:-/root}/.local/share"
ln -sfn "$DATA_DIR" "${HOME:-/root}/.local/share/mcpelauncher"

SETTINGS="$DATA_DIR/mcpelauncher-client-settings.txt"
mkdir -p "$(dirname "$SETTINGS")"
touch "$SETTINGS"
grep -q "^audio_backend=" "$SETTINGS" 2>/dev/null ||
  echo "audio_backend=sdl3" >> "$SETTINGS"

# --- Game options guardrails --------------------------------------------------
# Match the 64-bit launcher: only edit existing keys, so player visual choices
# are seeded once by the entry script and then left alone.
tune_game_options() {
  [ "${MCPE_PERFORMANCE_OPTIONS:-1}" = 1 ] || return
  local options_file
  while IFS= read -r options_file; do
    [ -f "$options_file" ] || continue
    set_option() {
      grep -q "^$1:" "$options_file" && sed -i "s#^$1:.*#$1:$2#" "$options_file"
    }
    set_option gfx_multithreaded_renderer "${MCPE_MULTITHREADED_RENDERER:-1}"
    [ -n "${MCPE_RENDER_DISTANCE:-}" ] && set_option gfx_viewdistance "$MCPE_RENDER_DISTANCE"
    [ -n "${MCPE_MAX_FPS:-}" ] && set_option gfx_max_framerate "$MCPE_MAX_FPS"
    set_option dev_file_watcher 0
    set_option content_log_file 0
    set_option content_log_gui 0
  done < <(find "$DATA_ROOT/mcpelauncher/games" -name options.txt 2>/dev/null)
}
tune_game_options

chmod +x "$BIN" 2>/dev/null

# Optional gptokeyb overlay (hotkeys); the SDL client handles the pad itself.
if [ -n "${GPTOKEYB:-}" ]; then
  $GPTOKEYB "mcpelauncher-client" &
fi

echo "=== launching 32-bit: version=$MCVER sdl=$SDL_VIDEODRIVER ==="
if [ "${MCPE_32BIT_TEE_LOG:-0}" = 1 ]; then
  "$BIN" -dg "$GAMEDIR/versions/$MCVER" ${ARGS:-} 2>&1 | tee "$LOG"
  status="${PIPESTATUS[0]}"
else
  "$BIN" -dg "$GAMEDIR/versions/$MCVER" ${ARGS:-} >"$LOG" 2>&1
  status="$?"
fi

[ -n "${GPTOKEYB:-}" ] && $ESUDO killall -9 gptokeyb 2>/dev/null
echo "--- exit: $status ---"
cleanup
exit "$status"
