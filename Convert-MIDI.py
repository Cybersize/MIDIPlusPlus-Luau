"""Create ASCII base64 sidecars for executor bridges that cannot read binary MIDI.

Usage: python Convert-MIDI.py [file.mid ... | folder ...]
With no arguments, converts MIDI files in Xeno's normal MIDIPlusPlus folder.
Original MIDI files stay untouched. No files are uploaded or downloaded.
SPDX-License-Identifier: GPL-3.0-only
"""
from pathlib import Path
import argparse
import base64
import os
import sys

EXTENSIONS = {".mid", ".midi", ".rmi"}
MAX_BYTES = 16 * 1024 * 1024


def convert_file(path):
    path = Path(path)
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        raise ValueError("file exceeds the player's 16 MiB limit")
    if not (data.startswith(b"MThd") or (data.startswith(b"RIFF") and data[8:12] == b"RMID")):
        raise ValueError("not a standard MIDI or RIFF/RMID file")
    encoded = base64.b64encode(data) + b"\n"
    destination = path.with_name(path.name + ".b64")
    if destination.exists() and destination.read_bytes() == encoded:
        return destination, False
    destination.write_bytes(encoded)
    return destination, True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="MIDI files or folders")
    arguments = parser.parse_args()
    inputs = [Path(value) for value in arguments.paths]
    if not inputs:
        local_app_data = os.environ.get("LOCALAPPDATA")
        if not local_app_data:
            parser.error("pass a MIDI file or folder")
        inputs = [Path(local_app_data) / "Xeno" / "workspace" / "MIDIPlusPlus"]
    files, errors, changed, seen = [], 0, 0, set()
    for value in inputs:
        if value.is_dir():
            files.extend(path for path in value.iterdir() if path.is_file() and path.suffix.lower() in EXTENSIONS)
        elif value.is_file() and value.suffix.lower() in EXTENSIONS:
            files.append(value)
        else:
            print(f"Not a MIDI file or folder: {value}", file=sys.stderr)
            errors += 1
    for path in sorted(files):
        identity = os.path.normcase(str(path.resolve()))
        if identity in seen:
            continue
        seen.add(identity)
        try:
            destination, created = convert_file(path)
            changed += int(created)
            print(("Created: " if created else "Current: ") + str(destination))
        except (OSError, ValueError) as error:
            print(f"Skipped {path.name}: {error}", file=sys.stderr)
            errors += 1
    print(f"{changed} sidecars created/updated; {len(seen)} MIDI files checked; {errors} errors.")
    return 1 if errors or not seen else 0


if __name__ == "__main__":
    sys.exit(main())
