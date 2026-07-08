# Support

Use GitHub issues for public bug reports and controller mapping reports.

## Known issues and fixes

- **No audio on muOS (game runs fine otherwise).** muOS Jacaranda runs
  PipeWire, which holds the ALSA device exclusively; older builds of this
  port fell back to raw ALSA and got "Device or resource busy". Fixed in
  1.4: the launcher now detects the PipeWire socket and routes audio through
  it. If audio is still silent, launch once with `MCPE_SDL_AUDIODRIVER=alsa`
  or `MCPE_ALSOFT_DRIVERS=pipewire,pulse,alsa` and attach `log.txt` to an
  issue.
- **UI looks slightly stretched or cut off on non-720x480 screens.** Fixed in
  1.4: the game window is now requested at the real panel size. Override with
  `MCPE_DISPLAY_WIDTH` / `MCPE_DISPLAY_HEIGHT` if your panel is detected
  wrong (check the `size=` line in `weston_launch.log`).

Include:

- device model
- firmware / OS version
- Minecraft APK version
- whether first-run extraction completed
- relevant lines from `minecraftbedrock/log.txt`
- relevant lines from `minecraftbedrock/weston_launch.log`

Do not include:

- APK files or links to APK files
- extracted game folders such as `versions/`
- `profiles/`, worlds, or account data
- `libminecraftpe.so`
- private server addresses, tokens, or account identifiers

If a report needs private game files to reproduce, it cannot be handled in a
public issue.
