#!/bin/bash
# Minecraft Bedrock 1.16 — separate entry with an ISOLATED profile.
# 1.16 predates RenderDragon and OreUI: classic renderer, classic UI with a
# working GUI Scale slider. Its worlds are separate from the newer versions'
# (older clients cannot open newer worlds), hence the dedicated profile.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTDIR="$SCRIPT_DIR"

try_game_dir() {
  [ -f "$1/run_bedrock.sh" ] && [ -f "$1/setup_apk.sh" ] &&
    { echo "$1"; return 0; }
  return 1
}

pick_game_dir() {
  local base parent pbase root
  try_game_dir "$SCRIPT_DIR/minecraftbedrock" && return
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

pick_116_version() {
  local preferred v
  # The original R36S port is known-good with 1.16.40.02. Newer 1.16 builds
  # may boot on some devices, but this dedicated entry should choose the
  # proven build when it is installed.
  for preferred in 1.16.40.02 1.16.201.01 1.16.221.01; do
    [ -d "$GAMEDIR/versions/$preferred" ] && { echo "$preferred"; return 0; }
  done
  for v in "$GAMEDIR/versions"/1.16*; do
    [ -d "$v" ] || continue
    basename "$v"
  done | sort -V | head -1
}

MCVER_OVERRIDE="$(pick_116_version)"
export MCVER_OVERRIDE
export MCPE_DATA_ROOT_OVERRIDE="$GAMEDIR/profiles/$MCVER_OVERRIDE"
export MCPE_RENDER_DISTANCE="${MCPE_RENDER_DISTANCE:-64}"
export MCPE_MAX_FPS="${MCPE_MAX_FPS:-40}"

if [ -z "$MCVER_OVERRIDE" ] || [ ! -d "$GAMEDIR/versions/$MCVER_OVERRIDE" ]; then
  echo "No Minecraft 1.16 version is installed."
  echo "Run the main 'Minecraft Bedrock' entry once to import legacy R36S"
  echo "versions, or put a 1.16 APK for your device ABI in $GAMEDIR/apk/."
  exit 1
fi

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
seed_116_options

exec bash "$PORTDIR/Minecraft Bedrock.sh"
