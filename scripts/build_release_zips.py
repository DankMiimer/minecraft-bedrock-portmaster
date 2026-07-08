#!/usr/bin/env python3
"""Build the release zips from the staging tree.

Produces, in --out-dir:
  minecraftbedrock-<version>.zip              universal (extract into ports/)
  minecraftbedrock-<version>-muos-sdroot.zip  muOS (extract at the SD root:
                                              ROMS/Ports/*.sh + ports/minecraftbedrock/)
  SHA256SUMS.txt                              checksums for both

Then runs check_release_safety.py against each zip. Building both variants
from one staging tree removes the manual layout/sync step that previously
had to be done by hand for every release.

Usage:
  python scripts/build_release_zips.py --staging ../staging --version 1.4
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import subprocess
import sys
import zipfile

EXCLUDE_NAMES = {".DS_Store", "Thumbs.db", "log.txt", "setup_error.txt", "__pycache__"}
EXCLUDE_SUFFIXES = (".pyc", ".part")
EXCLUDE_PREFIXES = ("fps-trace",)


def iter_staging_files(staging: pathlib.Path):
    for path in sorted(staging.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(staging)
        parts = rel.parts
        if any(p in EXCLUDE_NAMES for p in parts):
            continue
        if rel.name.endswith(EXCLUDE_SUFFIXES) or rel.name.startswith(EXCLUDE_PREFIXES):
            continue
        yield path, rel


def add_file(archive: zipfile.ZipFile, src: pathlib.Path, arcname: str) -> None:
    info = zipfile.ZipInfo(arcname)
    # Stable timestamps make rebuilt zips byte-comparable.
    info.date_time = (2026, 1, 1, 0, 0, 0)
    info.external_attr = (0o755 if arcname.endswith(".sh") or "/bin" in arcname else 0o644) << 16
    archive.writestr(info, src.read_bytes(), zipfile.ZIP_DEFLATED)


def build_zip(staging: pathlib.Path, out: pathlib.Path, layout: str, version: str) -> None:
    with zipfile.ZipFile(out, "w") as archive:
        for src, rel in iter_staging_files(staging):
            rel_posix = rel.as_posix()
            # Stamp the shipped version so the on-device updater can compare
            # against the latest release tag.
            if rel_posix == "minecraftbedrock/PORT_VERSION":
                info = zipfile.ZipInfo(rel_posix if layout == "universal"
                                       else f"ports/{rel_posix}")
                info.date_time = (2026, 1, 1, 0, 0, 0)
                info.external_attr = 0o644 << 16
                archive.writestr(info, version + "\n", zipfile.ZIP_DEFLATED)
                continue
            if layout == "universal":
                arcname = rel_posix
            elif layout == "muos-sdroot":
                if rel_posix.endswith(".sh") and len(rel.parts) == 1:
                    arcname = f"ROMS/Ports/{rel_posix}"
                elif rel.parts[0] == "minecraftbedrock":
                    arcname = f"ports/{rel_posix}"
                elif rel_posix == "README.md":
                    # Keep the README visible at the SD root (and the safety
                    # checker requires a root README with the disclaimer).
                    arcname = rel_posix
                else:
                    # Other docs and source_release ride along under
                    # ports/minecraftbedrock/.
                    arcname = f"ports/minecraftbedrock/{rel_posix}"
            else:
                raise ValueError(layout)
            add_file(archive, src, arcname)
    print(f"built {out} ({out.stat().st_size / 1024 / 1024:.1f} MB)")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging", type=pathlib.Path, required=True,
                        help="path to the staging tree (dist/staging)")
    parser.add_argument("--version", required=True, help="release version, e.g. 1.4")
    parser.add_argument("--out-dir", type=pathlib.Path, default=pathlib.Path("."),
                        help="output directory (default: cwd)")
    parser.add_argument("--skip-safety-check", action="store_true")
    args = parser.parse_args()

    staging = args.staging.resolve()
    if not (staging / "minecraftbedrock").is_dir():
        print(f"ERROR: {staging} has no minecraftbedrock/ payload dir", file=sys.stderr)
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    zips = []
    for layout, suffix in (("universal", ""), ("muos-sdroot", "-muos-sdroot")):
        out = args.out_dir / f"minecraftbedrock-{args.version}{suffix}.zip"
        build_zip(staging, out, layout, args.version)
        zips.append(out)

    sums_path = args.out_dir / "SHA256SUMS.txt"
    sums_path.write_text(
        "".join(f"{sha256(z)}  {z.name}\n" for z in zips), encoding="utf-8"
    )
    print(f"wrote {sums_path}")

    if not args.skip_safety_check:
        checker = pathlib.Path(__file__).with_name("check_release_safety.py")
        for z in zips:
            result = subprocess.run([sys.executable, str(checker), "--zip", str(z)])
            if result.returncode != 0:
                print(f"SAFETY CHECK FAILED: {z}", file=sys.stderr)
                return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
