# Changelog

## Unreleased (v1.4)

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
