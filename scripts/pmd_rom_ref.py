#!/usr/bin/env python3
"""Reference dump for verifying pmd_sky_sprites' in-game ROM reader.

Renders every species' chosen animation group (per data/anims.lua,
tried across the three /MONSTER packs the way lib/romread.lua does)
with scripts/pmd_rom_extract.py's parser and emits geometry, durations
and a pixel checksum as JSON.  scripts/pmd_rom_verify.lua computes the
same numbers with the mod's lib/romread.lua and compares.

Usage: pmd_rom_ref.py <rom.nds> > ref.json
"""

import importlib.util
import json
import pathlib
import re
import struct
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "pmd_rom_extract", HERE / "pmd_rom_extract.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

PACKS = ["/MONSTER/m_attack.bin", "/MONSTER/monster.bin",
         "/MONSTER/m_ground.bin"]

rom = pathlib.Path(sys.argv[1]).read_bytes()
files = m.nitrofs_files(rom)

anims = {}
anims_lua = (HERE.parent / "pmd_sky_sprites" / "data" / "anims.lua").read_text()
for dex, group in re.findall(r"\[(\d+)\] = { anim = \"\w+\", group = (\d+)",
                             anims_lua):
    anims[int(dex)] = int(group)


def entry(name, idx):
    s, e = files[name]
    pack = rom[s:e]
    if idx >= m.u32(pack, 4):
        return None
    off, size = struct.unpack("<II", pack[8 + idx * 8:16 + idx * 8])
    if size == 0:
        return None
    d = pack[off:off + size]
    if d[:5] == b"PKDPX":
        d = m.pkdpx(d)
    return d if d[:4] == b"SIR0" else None


def sheet(dex, group):
    for name in PACKS:
        d = entry(name, dex)
        if not d:
            continue
        try:
            r = m.render_group(m.Wan(d), group)
        except Exception:
            r = None
        if r:
            return r
    return None


out = {}
for dex in range(1, 252):
    group = anims.get(dex)
    if group is None:
        continue
    r = sheet(dex, group)
    if not r:
        continue
    n, durations, fw, fh, rows = r
    chk = 0
    for di, row in enumerate(rows):
        for f, canvas in enumerate(row):
            for i, (cr, cg, cb, ca) in enumerate(canvas):
                if ca:
                    chk = (chk + (di * 7919 + f * 104729 + i + 1)
                           * (cr + 2 * cg + 4 * cb + 8)) % 2147483647
    out[dex] = {"frames": n, "durations": durations,
                "fw": fw, "fh": fh, "chk": chk}
print(json.dumps(out))
