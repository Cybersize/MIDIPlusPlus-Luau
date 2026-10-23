"""ASCII MIDI cache/index for Windows executor bridges with narrow file paths.

Original filenames and bytes are retained. The index stores UTF-8 basenames in
base64 and refers only to generated ASCII cache filenames, never executable code.
SPDX-License-Identifier: GPL-3.0-only
"""
from pathlib import Path
import base64
import hashlib
import os
import tempfile

INDEX_NAME = "MIDIPlusPlus-files.txt"
CACHE_NAME = ".midipp-cache"
HEADER = b"MIDIPlusPlus files v1\n"
EXTENSIONS = {".mid", ".midi", ".rmi"}
MAX_BYTES = 16 * 1024 * 1024


def _write_if_changed(path, data):
    if path.is_file() and path.read_bytes() == data:
        return
    descriptor, temporary = tempfile.mkstemp(prefix="midipp-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def build_index(folder):
    folder = Path(folder).resolve()
    if not folder.is_dir():
        raise ValueError("MIDI folder does not exist")
    choices = {}
    for path in folder.iterdir():
        if not path.is_file():
            continue
        sidecar = path.name.lower().endswith(".b64")
        base = path.name[:-4] if sidecar else path.name
        if Path(base).suffix.lower() not in EXTENSIONS:
            continue
        key = base.casefold()
        if key not in choices or not sidecar:
            choices[key] = path
    if len(choices) > 4096:
        raise ValueError("The file index supports up to 4096 songs per folder")
    cache = folder / CACHE_NAME
    cache.mkdir(exist_ok=True)
    lines, skipped, originals = [], [], []
    for key, path in sorted(choices.items()):
        try:
            sidecar = path.name.lower().endswith(".b64")
            if path.stat().st_size > (24 if sidecar else 16) * 1024 * 1024:
                raise ValueError("MIDI exceeds the player's size limit")
            original = path.read_bytes()
            data = base64.b64decode(b"".join(original.split()), validate=True) if sidecar else original
            if len(data) > MAX_BYTES or not (data.startswith(b"MThd") or (data.startswith(b"RIFF") and data[8:12] == b"RMID")):
                raise ValueError("Not a standard MIDI or RIFF/RMID file")
            alias = hashlib.sha256(key.encode("utf-8")).hexdigest()
            _write_if_changed(cache / (alias + ".mid.b64"), base64.b64encode(data) + b"\n")
            lines.append(base64.b64encode(path.name.encode("utf-8")) + b"\t" + alias.encode("ascii") + b"\n")
            originals.append(path.name)
        except (OSError, ValueError) as error:
            skipped.append({"name": path.name, "error": str(error)})
    _write_if_changed(folder / INDEX_NAME, HEADER + b"".join(lines))
    return {"indexed": len(lines), "skipped": skipped, "names": originals, "index": str(folder / INDEX_NAME)}
