"""Create ASCII base64 sidecars for executor bridges that cannot read binary MIDI.

Usage: python Convert-MIDI.py [file.mid ... | folder ...]
With no arguments, detects Project Real's workspace, then Xeno's as a fallback.
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
    from midi_index import build_index, executor_target
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="MIDI files or folders")
    parser.add_argument("--executor", choices=("real", "xeno"), help="Choose a conventional executor workspace explicitly")
    arguments = parser.parse_args()
    inputs = [Path(value) for value in arguments.paths]
    if not inputs:
        name, folder = executor_target(arguments.executor)
        if not folder.is_dir():
            parser.error(f"{name}'s MIDIPlusPlus folder was not found at {folder}; pass your actual MIDI folder")
        print(f"Using {name}: {folder}")
        inputs = [folder]
    files, errors, changed, seen, folders = [], 0, 0, set(), set()
    for value in inputs:
        if value.is_dir():
            folders.add(value.resolve())
            files.extend(path for path in value.iterdir() if path.is_file() and path.suffix.lower() in EXTENSIONS)
        elif value.is_file() and value.suffix.lower() in EXTENSIONS:
            folders.add(value.resolve().parent)
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
    indexed = 0
    for folder in sorted(folders):
        try:
            result = build_index(folder)
            indexed += result["indexed"]
            print(f"Filename compatibility index: {result['indexed']} songs in {folder}")
            for skipped in result["skipped"]:
                print(f"Index skipped {skipped['name']}: {skipped['error']}", file=sys.stderr)
                errors += 1
        except (OSError, ValueError) as error:
            print(f"Could not prepare filename compatibility for {folder}: {error}", file=sys.stderr)
            errors += 1
    print(f"{changed} sidecars created/updated; {len(seen)} MIDI files checked; {errors} errors.")
    return 1 if errors or not (seen or indexed) else 0


if __name__ == "__main__":
    sys.exit(main())
