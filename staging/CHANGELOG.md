# Changelog

## v1.6 (2026-07-10)

- **New launcher menu.** Starting **Minecraft Bedrock** now opens a full
  controller-driven launcher (LÖVE) instead of the bare version list, and it
  now also runs on fbdev devices (Knulli/muOS H700) — previously it only
  appeared on kmsdrm/ROCKNIX devices:
  - **Versions**: switch the active version (remembered across launches) or
    delete installed versions; worlds/profiles are never touched.
  - **Install APK**: install new versions from APK files in `apk/` — a
    single file or a whole Google Play split set — and delete the APK files
    afterwards, all from the device.
  - **Settings** (persisted in `config/settings.cfg`, applied every launch):
    FPS cap, render distance in chunks (can go below the in-game slider's
    minimum), 64/32-bit client override, UI scale, VSync, performance
    governor, options auto-tune, FPS logging.
  - **Backup**: archive worlds, game options, and launcher settings into
    `backups/` as tar.gz, and restore or delete archives — all on-device.
  - **Help**: short on-device troubleshooting guide.
  - The menu stops/restores the CFW frontend itself where needed, and any
    menu crash falls back to the old newest-version autostart.
  - The menu UI is original to this port: procedural pixel-art chrome
    (no image assets; the old gameplay-screenshot background is gone) with
    the OFL-licensed Monocraft font, sized for small handheld screens.
  - Button mapping matches the printed labels on the pad (confirm on the
    button printed A, back on B, delete on X). Whether the CFW's SDL mapping
    is positional (H700 family) or label-based (RG DS) is detected per pad
    GUID; `MCPE_MENU_CONFIRM=a|b` overrides it for unlisted pads.
  - FPS cap covers 10–120 in 5 fps steps.
  - Pressing Play shows a **LAUNCHING pop-up** with the chosen version and a
    progress bar; it stays on screen while the game boots, so the seconds
    between the menu and the game no longer look like a freeze.
  - **3D widget set**: every menu row is a chunky extruded 3D button (hard
    outline, lit top edge, darker bottom side; the selected one lifts and
    glows green), On/Off settings are large toggle switches with I/O marks,
    FPS cap and render distance are thick sliders with a notched groove and
    a two-tone striped fill, main-menu entries carry 8×8 pixel icons, footer
    hints are 3D keycaps, and the LAUNCHING pop-up uses a sweeping
    slider-style loading bar. Knobs are chamfered octagons with grip lines —
    an original silhouette rather than square game-style widgets.
- Explicit FPS-cap / render-distance / VSync choices are now written into
  the game's `options.txt` even on a brand-new profile (previously they only
  applied if the game had already written the key) and are applied
  independently of the `MCPE_PERFORMANCE_OPTIONS` guardrail toggle.
- Fixed: an APK left in `apk/` after installation no longer makes every
  launch fail with "version already exists" — with the menu available,
  installs are user-driven; on menu-less devices a failed re-extraction now
  falls back to the installed versions instead of aborting.
- The CFW's SDL controller mapping is now actually exported to the menu
  (it was fetched but never passed on), fixing swapped/misplaced buttons in
  the selector on some devices.
- `setup_apk.sh` accepts explicit APK paths as arguments (used by the menu).
- `port.json` and the release zip now ship only the main **Minecraft
  Bedrock** entry; version selection (including 1.16) and port updates live
  inside the launcher menu.

## v1.5.1 (2026-07-09)

- Fixed the port not launching on Knulli when installed in the v1.5 split
  layout (`roms/ports/` scripts + `ports/minecraftbedrock/` payload): the
  PortMaster control files the main entry sources can clobber `SCRIPT_DIR`,
  making the game folder resolve to `/minecraftbedrock`. The entry now
  restores its script directory after sourcing. Verified on an RG34XX-SP
  running Knulli (Scarab).
- Fixed silent audio on Pulse-served systems (Knulli and ROCKNIX,
  pipewire-pulse): since v1.4 the launcher was started with
  `SDL_AUDIO_DRIVER=openal` — that is SDL3's effective hint name and
  "openal" is not an SDL3 audio driver, so SDL3's audio subsystem failed to
  initialize and the game was mute. `SDL_AUDIO_DRIVER` is now only passed
  when a driver is explicitly selected (the muOS PipeWire-without-Pulse
  path, or the `MCPE_SDL_AUDIODRIVER` override); otherwise SDL3 keeps its
  default driver order and picks PulseAudio. muOS is unaffected. Verified
  on an RG DS running ROCKNIX and an RG34XX-SP running Knulli.

## v1.5 (2026-07-09)

- **One release zip for everything.** The universal and `-muos-sdroot`
  variants are replaced by a single `minecraftbedrock-<version>.zip` that
  installs by extracting it at the SD card / share root — no install
  scripts, no manual file placement. The launch entries ship at both
  `roms/ports/` (muOS `ROMS/Ports` via FAT case-insensitivity, Knulli
  `roms/ports`) and `ports/` (ROCKNIX-style layouts); the port payload
  ships once at `ports/minecraftbedrock/`. The classic
  "everything together in your ports folder" layout still works — the
  launch entries look next to themselves first.
- The **Minecraft Bedrock Update** entry understands the new zip layout
  (and the old one) and now also finds split installs where the scripts
  live in `roms/ports/` and the payload in `ports/` at the same root.
  Updating from v1.4/v1.4.1 with the old updater still works: the new
  zip is rejected safely — extract the v1.5 zip once by hand, after
  which in-place updates resume.
- Removed the PC-side `tools/prepare_sd` scripts — the single zip made
  them unnecessary.
- Confirmed working on muOS 2601 (RG34XX-SP), including audio; docs now
  describe the unified install on muOS, Knulli, and ROCKNIX.

## v1.4.1 (2026-07-09)

- Actually fixed silent audio on muOS (PipeWire without a Pulse socket).
  v1.4's approach could not work: the shipped client's static SDL3 has no
  PipeWire driver compiled in, so `SDL_AUDIODRIVER=pipewire,alsa` silently
  degraded to raw ALSA — and PipeWire holds the sound card exclusively
  ("Device or resource busy"). On top of that, muOS's minimal ALSA config
  does not advertise a `default` device in the namehint list, which SDL3
  requires before it will open `default`, so SDL3 opened the raw card
  directly. The port now ships `alsa/pipewire-overlay.conf` and, when it
  detects PipeWire with no Pulse socket, generates a private ALSA config
  (`ALSA_CONFIG_PATH`) routing `default`/`sysdefault` through the system's
  ALSA→PipeWire plugin. Verified on an RG34XX-SP running muOS 2601
  Jacaranda: active in-game PipeWire stream, audible sound. Knulli and
  ROCKNIX are unaffected (they take the Pulse path); disable with
  `MCPE_ALSA_PIPEWIRE=0`.
- The port README shipped inside v1.4 zips still described an internal R36S
  test build in its Download section; it now matches the public release.

## v1.4 (2026-07-08)

- Fixed silent audio on PipeWire-without-Pulse systems (muOS Jacaranda):
  raw ALSA fell back to "Device or resource busy" because PipeWire holds the
  device exclusively. The launcher now detects the PipeWire socket and routes
  SDL audio through it (`pipewire,alsa`), and exports `PULSE_SERVER` when a
  Pulse socket lives in a nonstandard location. Knulli/ROCKNIX unchanged.
- Fixed the game laying its UI out for 720x480 on other panels (e.g. 640x480
  RG35XX-H reported `getScreenWidth=720`): the client window is now requested
  at the real panel size via `-ww`/`-wh`.
- APK setup now fails fast with specific on-screen reasons: PairIP 1.26+
  Play builds, non-ARM ABIs (listing what was found), missing split parts,
  and corrupt archives — instead of a generic "extraction FAILED".
- Added PC-side SD preparation tools (`tools/prepare_sd.ps1` / `.sh`): verify
  the release zip, lay files out for Knulli/muOS/ROCKNIX, and validate the
  APK on the computer before the first on-device launch.
- Added `scripts/build_release_zips.py` + CI workflow: builds the universal
  and muOS SD-root zips from one staging tree with checksums and the content
  safety check.
- Added a **Minecraft Bedrock Update** Ports entry: downloads the latest
  release from GitHub and updates the port's scripts/binaries in place —
  worlds, settings, and installed game versions are never touched. Ships
  with a `PORT_VERSION` stamp (written by the release build script).
- Replaced the menu fonts with Monocraft (SIL OFL 1.1) — the previous
  fan-made fonts had unclear/personal-use-only licensing and could not be
  redistributed cleanly. License text added to `licenses/`.

## v1.4-r36s-test

- Added a dual-ABI launch flow: 64-bit aarch64 EGLUT/Weston remains the
  default for tested 64-bit devices, while RK3326/R36S-class devices can run
  the bundled 32-bit armhf SDL client from the working R36S port.
- Fixed the R36S/armhf packaging path by restoring bionic `libc.so`/`libm.so`
  shim visibility during APK extraction and launch.
- Added ABI auto-selection and `MCPE_ABI_OVERRIDE=armhf|arm64` for testing
  dArkOS/DarkOS RE, Aurknix, and ArkOS-for-clone variants.

## v1.3.1

- Fixed silent audio on ALSA-only systems with no PulseAudio/PipeWire server
  (e.g. muOS): the launcher now detects the missing server and routes its
  OpenAL output to ALSA automatically. Knulli and ROCKNIX are unchanged.
  Override with `MCPE_ALSOFT_DRIVERS`.

## v1.3

- Added muOS compatibility for H700 devices: split `/roms/Ports` + `/ports`
  install layout, `MUOS/PortMaster` runtime lookup, muOS frontend stop/restart,
  and Mali device-node fallback.
- Packaged a manual-install release for aarch64 handhelds.
- Added support for user-supplied single APKs and Google Play split APKs.
- Added a separate 1.16.221.01 launch entry with isolated profile data.
- Documented that 1.16.221.01 has a working GUI Scale slider and runs
  perfectly without stutters on tested devices.
- Included GPL source patches and license texts for shipped components.
- Added legal, support, credit, testing, checksum, and release-safety docs.
