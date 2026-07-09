#!/bin/bash
# Configure and run the EGLUT mcpelauncher client through the Weston/crusty
# stack. Derived from the RG34XX-SP production `_device_run_eglut.sh`.
GAMEDIR="${GAMEDIR:?run via 'Minecraft Bedrock.sh'}"
cd "$GAMEDIR" || exit 1

BIN64="$GAMEDIR/bin/mcpelauncher-client"
BIN32="$GAMEDIR/bin32/mcpelauncher-client"
export BIN_OVERRIDE="$BIN64"
export EXTRA_LIB="$GAMEDIR/libs.aarch64"
export MCVER_OVERRIDE="${MCVER_OVERRIDE:?no version selected}"
export MCPE_DATA_ROOT_OVERRIDE="${MCPE_DATA_ROOT_OVERRIDE:-$GAMEDIR/profiles/default}"

# --- Architecture (ABI) selection ---------------------------------------------
# The port ships two clients: bin/ (aarch64 EGLUT via Weston/crusty — Knulli
# H700, muOS, ROCKNIX) and bin32/ (armhf SDL3 direct-kmsdrm from the R36S
# port — RK3326-class devices with a real /dev/dri and armhf multilib). A
# version dir can carry either or both ABIs; pick per what is installed and
# what the device can run. The 64-bit client needs ~200 MB more RAM, so
# low-memory devices (R36S 512 MB) default to 32-bit when both are available.
V_HAS64=0 V_HAS32=0
[ -f "$GAMEDIR/versions/$MCVER_OVERRIDE/lib/arm64-v8a/libminecraftpe.so" ] && V_HAS64=1
[ -f "$GAMEDIR/versions/$MCVER_OVERRIDE/lib/armeabi-v7a/libminecraftpe.so" ] && V_HAS32=1
ARM64_USABLE=0
if [ -f "$BIN64" ] &&
   { [ -e /lib/ld-linux-aarch64.so.1 ] || [ -e /usr/lib/ld-linux-aarch64.so.1 ] ||
     [ "$(uname -m 2>/dev/null)" = aarch64 ]; }; then
  ARM64_USABLE=1
fi
ARMHF_USABLE=0
if [ -f "$BIN32" ] &&
   { [ -e /lib/ld-linux-armhf.so.3 ] || [ -e /usr/lib32/ld-linux-armhf.so.3 ] ||
     [ -e /usr/arm-linux-gnueabihf/lib/ld-linux-armhf.so.3 ]; } &&
   [ -e /dev/dri/card0 ]; then
  ARMHF_USABLE=1
fi
MEM_KB="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
ABI="${MCPE_ABI_OVERRIDE:-}"
case "$ABI" in
  "") ;;
  armhf|arm32|armv7|armeabi-v7a|32) ABI=armhf ;;
  arm64|aarch64|arm64-v8a|64) ABI=arm64 ;;
  *)
    echo "ERROR: unknown MCPE_ABI_OVERRIDE '$ABI' (use armhf or arm64)."
    exit 1
    ;;
esac
if [ -z "$ABI" ]; then
  if [ "$V_HAS64" = 1 ] && [ "$ARM64_USABLE" = 1 ] &&
     [ "$V_HAS32" = 1 ] && [ "$ARMHF_USABLE" = 1 ]; then
    if [ "$ARMHF_USABLE" = 1 ] && [ "$MEM_KB" -gt 0 ] && [ "$MEM_KB" -lt 1100000 ]; then
      ABI=armhf
    else
      ABI=arm64
    fi
  elif [ "$V_HAS32" = 1 ] && [ "$ARMHF_USABLE" = 1 ]; then
    ABI=armhf
  elif [ "$V_HAS64" = 1 ] && [ "$ARM64_USABLE" = 1 ]; then
    ABI=arm64
  elif [ "$V_HAS32" = 1 ]; then
    ABI=armhf
  else
    ABI=arm64
  fi
fi
if [ "$ABI" = arm64 ] && [ "$V_HAS64" = 0 ]; then
  echo "ERROR: version $MCVER_OVERRIDE has no 64-bit (arm64-v8a) libraries."
  [ "$V_HAS32" = 1 ] && echo "Install an arm64 APK or launch with MCPE_ABI_OVERRIDE=armhf on an armhf-capable R36S/RK3326 setup."
  exit 1
fi
if [ "$ABI" = armhf ] && [ "$V_HAS32" = 0 ]; then
  echo "ERROR: version $MCVER_OVERRIDE has no 32-bit (armeabi-v7a) libraries."
  [ "$V_HAS64" = 1 ] && echo "Install an armeabi-v7a APK or launch with MCPE_ABI_OVERRIDE=arm64 on an aarch64 setup."
  exit 1
fi
if [ "$ABI" = armhf ] && [ "$ARMHF_USABLE" = 0 ]; then
  if [ -z "${MCPE_ABI_OVERRIDE:-}" ] && [ "$V_HAS64" = 1 ] && [ "$ARM64_USABLE" = 1 ]; then
    echo "32-bit path unavailable on this device (needs /dev/dri + armhf multilib); using 64-bit"
    ABI=arm64
  else
    echo "ERROR: version $MCVER_OVERRIDE is 32-bit only, but this device cannot run"
    echo "the 32-bit client (needs a real /dev/dri and armhf multilib, e.g."
    echo "R36S/RK3326 dArkOS, Aurknix, DarkOS RE, or ArkOS-for-clone builds)."
    exit 1
  fi
fi
if [ "$ABI" = arm64 ] && [ "$ARM64_USABLE" = 0 ]; then
  if [ -z "${MCPE_ABI_OVERRIDE:-}" ] && [ "$V_HAS32" = 1 ] && [ "$ARMHF_USABLE" = 1 ]; then
    echo "64-bit path unavailable on this device; using 32-bit"
    ABI=armhf
  else
    echo "ERROR: version $MCVER_OVERRIDE needs the 64-bit client, but this device"
    echo "cannot run it (needs aarch64 userspace/loader). Install an armeabi-v7a"
    echo "APK for R36S/RK3326-class 32-bit systems."
    exit 1
  fi
fi
echo "ABI: $ABI (version has: 64=$V_HAS64 32=$V_HAS32, usable: 64=$ARM64_USABLE 32=$ARMHF_USABLE, mem=${MEM_KB}kB)"
if [ "$ABI" = armhf ]; then
  export PORT_32BIT=Y
fi
if command -v pm_platform_helper >/dev/null 2>&1; then
  if [ "$ABI" = armhf ]; then
    pm_platform_helper "$BIN32" || true
  else
    pm_platform_helper "$BIN64" || true
  fi
fi
if [ "$ABI" = armhf ]; then
  exec bash "$GAMEDIR/run_bedrock32.sh"
fi

# --- Weston runtime (weston_pkg_0.2) — 64-bit EGLUT path only -----------------
# Resolved here (not in the entry script) so a 32-bit-only install never needs
# it. weston_launch.sh requires WESTON_SQUASH.
if [ -z "${WESTON_SQUASH:-}" ]; then
  PM_DIR="${PM_DIR:-$(printf '\120\157\162\164\115\141\163\164\145\162')}"
  find_weston_squash() {
    local c
    for c in "${controlfolder:-/nonexistent}/libs/weston_pkg_0.2.squashfs" \
             "${controlfolder:-/nonexistent}/libs/weston_pkg_0.2.aarch64.squashfs" \
             "$GAMEDIR/runtime/weston_pkg_0.2.squashfs" \
             "$GAMEDIR/runtime/weston_pkg_0.2.aarch64.squashfs" \
             "/mnt/mmc/MUOS/$PM_DIR/libs/weston_pkg_0.2.squashfs" \
             "/mnt/mmc/MUOS/$PM_DIR/libs/weston_pkg_0.2.aarch64.squashfs" \
             "/mnt/sdcard/MUOS/$PM_DIR/libs/weston_pkg_0.2.squashfs" \
             "/mnt/sdcard/MUOS/$PM_DIR/libs/weston_pkg_0.2.aarch64.squashfs"; do
      [ -f "$c" ] && { echo "$c"; return 0; }
    done
    return 1
  }
  WESTON_SQUASH="$(find_weston_squash)" || {
    echo "Weston runtime not found — downloading (53 MB, one time)..."
    mkdir -p "$GAMEDIR/runtime"
    PM_ORG="$(printf '\120\157\162\164\163\115\141\163\164\145\162')"
    URL="https://raw.githubusercontent.com/$PM_ORG/$PM_DIR-New/main/runtimes/weston_pkg_0.2.aarch64.squashfs"
    TARGET="$GAMEDIR/runtime/weston_pkg_0.2.aarch64.squashfs"
    if command -v curl >/dev/null 2>&1; then
      curl -L -o "$TARGET.part" "$URL" && mv "$TARGET.part" "$TARGET"
    elif command -v wget >/dev/null 2>&1; then
      wget -O "$TARGET.part" "$URL" && mv "$TARGET.part" "$TARGET"
    fi
    WESTON_SQUASH="$(find_weston_squash)" || {
      echo "Could not obtain the Weston runtime (needed for the 64-bit path)."
      echo "Connect to WiFi and relaunch, or copy a compatible"
      echo "weston_pkg_0.2.aarch64.squashfs into minecraftbedrock/runtime/."
      exit 1
    }
  }
  export WESTON_SQUASH
fi

# Backing SDL video driver for crusty, per display stack:
#  - sway compositor (ROCKNIX): crusty nests under sway -> wayland
#  - Allwinner fbdev+/dev/disp (Knulli H700): the blob's fbdev driver -> mali
#  - otherwise: x11
if [ -z "${SDL_DRIVER_OVERRIDE:-}" ]; then
  if pidof sway >/dev/null 2>&1; then
    SDL_DRIVER_OVERRIDE=wayland
  elif [ -e /dev/disp ] ||
       { [ "${MCPE_IS_MUOS:-0}" = 1 ] && { [ -e /dev/mali ] || [ -e /dev/mali0 ]; }; }; then
    SDL_DRIVER_OVERRIDE=mali
  else
    SDL_DRIVER_OVERRIDE=x11
  fi
fi
export SDL_DRIVER_OVERRIDE

# The Westonpack 0.2 crusty EGL shim reports success from eglMakeCurrent
# without binding its backing SDL context; the EGLUT client bridges that
# context explicitly. Required on libmali/no-DRM devices (H700 family).
# The bridge reads private crusty offsets specific to weston_pkg_0.2 aarch64,
# hence the pinned runtime.
export GAMEWINDOW_EGLUT_CRUSTY_CONTEXT="${GAMEWINDOW_EGLUT_CRUSTY_CONTEXT:-1}"
# Crusty's direct Mali window has no real X11 FocusIn event; force focus so
# linux-gamepad polls the pad.
export GAMEWINDOW_EGLUT_FORCE_FOCUS="${GAMEWINDOW_EGLUT_FORCE_FOCUS:-1}"

export MCPE_REPORTED_DISPLAY_SCALE="${MCPE_REPORTED_DISPLAY_SCALE:-1}"
export MCPE_DISABLE_AUTO_COMPACTION="${MCPE_DISABLE_AUTO_COMPACTION:-0}"

# Thread layout measured on a 4x Cortex-A53 (H700): render thread on core 3,
# simulation ("MINECRAFT MAIN") on core 2, chunk workers on 0-1, and the game
# sees 2 CPUs so its worker pools fit. Cut stutters ~4x. Only applied on
# 4-core devices; elsewhere the engine keeps its defaults.
# busybox systems (ROCKNIX) have no nproc.
NCORES="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 0)"
if [ "$NCORES" = 4 ]; then
  export MCPE_PIN_RENDER_CORE="${MCPE_PIN_RENDER_CORE-3}"
  export MCPE_PIN_MAIN_CORE="${MCPE_PIN_MAIN_CORE-2}"
  export MCPE_PIN_OTHER_CORES="${MCPE_PIN_OTHER_CORES-0-1}"
  export MCPE_FAKE_NPROC="${MCPE_FAKE_NPROC-2}"
fi
export MCPE_AFFINITY_LOG="${MCPE_AFFINITY_LOG:-0}"

chmod +x "$BIN_OVERRIDE" 2>/dev/null

# Audio: the launcher's own pulseaudio backend is the default and works on
# Knulli and ROCKNIX (pipewire-pulse). Optionally, a HOST (glibc aarch64)
# FMOD Engine library obtained from fmod.com can be dropped at
# $GAMEDIR/fmod/libfmod.so.12.0 — the launcher then uses real FMOD (looked
# up via $XDG_DATA_HOME/mcpelauncher/lib/native/<abi>/). The game's own
# Android libfmod.so does NOT work here (bionic, not glibc).
FMOD_HOST="$GAMEDIR/fmod/libfmod.so.12.0"
FMOD_DST="$MCPE_DATA_ROOT_OVERRIDE/mcpelauncher/lib/native/arm64-v8a/libfmod.so.12.0"
if [ -f "$FMOD_HOST" ]; then
  mkdir -p "$(dirname "$FMOD_DST")" 2>/dev/null
  cp -f "$FMOD_HOST" "$FMOD_DST" 2>/dev/null
else
  rm -f "$FMOD_DST" 2>/dev/null
fi

# Audio output backend. When there is no host FMOD, the launcher mixes the
# game's audio through its SDL/OpenAL fallback chain. Three device families:
#  - Pulse-compatible server up (Knulli, ROCKNIX: pipewire-pulse) — default
#    path works; export PULSE_SERVER when the socket is in a nonstandard spot.
#  - PipeWire WITHOUT a pulse socket (muOS Jacaranda: PIPEWIRE_RUNTIME_DIR=/run)
#    — raw ALSA fails with "Device or resource busy" because PipeWire holds
#    the device exclusively; route SDL audio to the pipewire driver instead.
#  - Bare ALSA (older minimal builds) — force OpenAL Soft/SDL onto ALSA.
# MCPE_SDL_AUDIODRIVER is consumed by weston_launch.sh (its default stays
# "openal", the value production Knulli devices are verified with).
# Overrides: MCPE_ALSOFT_DRIVERS, MCPE_SDL_AUDIODRIVER.
find_pulse_socket() {
  local s
  for s in "${PULSE_RUNTIME_PATH:-/nonexistent}/native" \
           "${XDG_RUNTIME_DIR:-/run/user/$(id -u 2>/dev/null)}/pulse/native" \
           /run/user/*/pulse/native /run/pulse/native /tmp/pulse-*/native; do
    [ -S "$s" ] && { echo "$s"; return 0; }
  done
  return 1
}
find_pipewire_socket() {
  local s
  for s in "${PIPEWIRE_RUNTIME_DIR:-/nonexistent}/pipewire-0" \
           "${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-0" \
           /run/pipewire-0 /run/user/*/pipewire-0 /tmp/pipewire-0; do
    [ -S "$s" ] && { echo "$s"; return 0; }
  done
  return 1
}
if [ -n "${MCPE_ALSOFT_DRIVERS:-}" ]; then
  export ALSOFT_DRIVERS="$MCPE_ALSOFT_DRIVERS"
elif [ -z "${ALSOFT_DRIVERS:-}" ]; then
  pulse_sock=""
  pulse_up=0
  if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    pulse_up=1
  elif pidof pulseaudio >/dev/null 2>&1 || pidof pipewire-pulse >/dev/null 2>&1; then
    pulse_up=1
  elif pulse_sock="$(find_pulse_socket)"; then
    pulse_up=1
    export PULSE_SERVER="unix:$pulse_sock"
    echo "audio: pulse socket at $pulse_sock"
  fi
  if [ "$pulse_up" = 0 ]; then
    if pw_sock="$(find_pipewire_socket)"; then
      # PipeWire owns the ALSA device; talk to it directly via SDL's
      # pipewire driver (alsa stays in the list as a fallback).
      [ -z "${PIPEWIRE_RUNTIME_DIR:-}" ] &&
        export PIPEWIRE_RUNTIME_DIR="$(dirname "$pw_sock")"
      export MCPE_SDL_AUDIODRIVER="${MCPE_SDL_AUDIODRIVER:-pipewire,alsa}"
      export ALSOFT_DRIVERS="pipewire,pulse,alsa"
      echo "audio: PipeWire server (no pulse socket) at $pw_sock -> SDL pipewire driver"
      # The shipped SDL3 has no pipewire driver compiled in, so audio really
      # goes SDL3 -> ALSA. Raw/sysdefault ALSA devices are EBUSY while
      # PipeWire runs; give the game an ALSA config whose default AND
      # sysdefault route through the pipewire ALSA plugin (verified on muOS
      # 2601 Jacaranda / RG34XX-SP). Disable with MCPE_ALSA_PIPEWIRE=0.
      pw_alsa_plugin=0
      for p in /usr/lib*/alsa-lib/libasound_module_pcm_pipewire.so \
               /usr/lib/*/alsa-lib/libasound_module_pcm_pipewire.so; do
        [ -f "$p" ] && { pw_alsa_plugin=1; break; }
      done
      if [ "${MCPE_ALSA_PIPEWIRE:-1}" != 0 ] &&
         [ "$pw_alsa_plugin" = 1 ] &&
         [ -z "${ALSA_CONFIG_PATH:-}" ] &&
         [ -f /usr/share/alsa/alsa.conf ] &&
         [ -f "$GAMEDIR/alsa/pipewire-overlay.conf" ]; then
        if cat /usr/share/alsa/alsa.conf "$GAMEDIR/alsa/pipewire-overlay.conf" \
             > /tmp/mcpe_alsa_pipewire.conf 2>/dev/null; then
          export ALSA_CONFIG_PATH=/tmp/mcpe_alsa_pipewire.conf
          echo "audio: ALSA default/sysdefault routed via pipewire plugin (ALSA_CONFIG_PATH)"
        fi
      fi
    else
      export ALSOFT_DRIVERS=alsa
      echo "audio: no PulseAudio/PipeWire server found -> routing OpenAL to ALSA"
    fi
  fi
fi

# --- Launcher settings + controller mapping ----------------------------------
SETTINGS="$MCPE_DATA_ROOT_OVERRIDE/mcpelauncher/mcpelauncher-client-settings.txt"
mkdir -p "$(dirname "$SETTINGS")"
touch "$SETTINGS"

# game-window's EGLUT backend does not consume SDL_GAMECONTROLLERCONFIG; it
# reads gamecontrollerdb.txt from the launcher data dir, and its evdev button
# indices differ from SDL's. Mapping lines are matched by controller GUID, so
# all known-device lines are concatenated and the right one is picked at
# runtime. Contribute new lines in controls/ (see controls/README.md).
GAMEPAD_DB="$(dirname "$SETTINGS")/gamecontrollerdb.txt"
cat "$GAMEDIR/controls/"*.gamecontrollerdb.txt > "$GAMEPAD_DB" 2>/dev/null

# Unknown pad? Auto-generate a standard-layout mapping line for any connected
# gamepad whose GUID is not covered above (genmap.py replicates the backend's
# button numbering). Users on untested devices get working default controls;
# the generated line is logged so it can be contributed back.
if command -v python3 >/dev/null 2>&1; then
  KNOWN_GUIDS="$(cut -d, -f1 "$GAMEPAD_DB" 2>/dev/null | tr '\n' ' ')"
  GENERATED="$(python3 "$GAMEDIR/genmap.py" $KNOWN_GUIDS 2>/dev/null)"
  if [ -n "$GENERATED" ]; then
    echo "Auto-generated controller mapping (please report/contribute):"
    echo "$GENERATED"
    echo "$GENERATED" >> "$GAMEPAD_DB"
  fi
fi

set_kv() {
  if grep -q "^$1=" "$SETTINGS" 2>/dev/null; then
    sed -i "s#^$1=.*#$1=$2#" "$SETTINGS"
  else
    echo "$1=$2" >> "$SETTINGS"
  fi
}
set_kv enable_imgui "${IMGUI:-false}"   # imgui's GL loader crashes on this path
set_kv scale "${MCPE_UI_DENSITY_SCALE:-2}"

# --- Game options guardrails --------------------------------------------------
# Do not fight the player's in-game settings; only guard the known-good
# renderer flag, disable dev logging, and honour explicit env pins.
tune_game_options() {
  [ "${MCPE_PERFORMANCE_OPTIONS:-1}" = 1 ] || return
  local options_file
  while IFS= read -r options_file; do
    [ -f "$options_file" ] || continue
    set_option() {
      grep -q "^$1:" "$options_file" && sed -i "s#^$1:.*#$1:$2#" "$options_file"
    }
    # Multithreaded renderer OFF does not submit static chunk draws on this
    # EGLUT/crusty/libmali stack — keep it ON.
    set_option gfx_multithreaded_renderer "${MCPE_MULTITHREADED_RENDERER:-1}"
    [ -n "${MCPE_RENDER_DISTANCE:-}" ] && set_option gfx_viewdistance "$MCPE_RENDER_DISTANCE"
    [ -n "${MCPE_MAX_FPS:-}" ] && set_option gfx_max_framerate "$MCPE_MAX_FPS"
    set_option dev_file_watcher 0
    set_option content_log_file 0
    set_option content_log_gui 0
  done < <(find "$MCPE_DATA_ROOT_OVERRIDE/mcpelauncher/games" -name options.txt 2>/dev/null)
}
tune_game_options

export APP_EXTRA_ARGS="${ARGS:-}"
GFX="${GFX:-crusty_x11egl}"
TMO="${TMO:-0}"

# Opt-in FPS measurement: MCPE_MEASURE_FPS=1 records a frame trace and prints
# a summary on exit. No overhead unless enabled.
FPS_TRACE=""
if [ "${MCPE_MEASURE_FPS:-0}" = 1 ]; then
  FPS_TRACE="$GAMEDIR/fps-trace-$(date +%H%M%S).csv"
  export MCPE_FRAME_METRICS="$FPS_TRACE"
fi

echo "=== launching: version=$MCVER_OVERRIDE gfx=$GFX cores=$NCORES ==="
bash "$GAMEDIR/weston_launch.sh" "$TMO" "$GFX"

if [ -n "$FPS_TRACE" ] && [ -s "$FPS_TRACE" ]; then
  echo "=== FPS SUMMARY ($FPS_TRACE) ==="
  awk -F, 'NR>1 && $3+0>2000000 {  # skip first ~2s of load
             d=$3-p; if(p>0 && d>0){n++; s+=d; a[n]=d} p=$3
           }
           END{
             if(n<10){print "  not enough frames"; exit}
             asort(a);
             med=a[int(n/2)];
             fps=1000000/med;
             # percent of frames at >=58fps (<=17240us) and >=30fps
             for(i=1;i<=n;i++){ if(a[i]<=17240)c60++; if(a[i]<=33333)c30++ }
             printf "  frames=%d  median=%.1fms (%.1f fps)  mean=%.1ffps\n", n, med/1000, fps, 1000000/(s/n);
             printf "  %%>=58fps=%.0f%%  %%>=30fps=%.0f%%  p99frame=%.1fms\n", 100*c60/n, 100*c30/n, a[int(n*0.99)]/1000
           }' "$FPS_TRACE"
fi
