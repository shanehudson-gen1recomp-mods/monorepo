#!/usr/bin/env python3
"""Extract in-air animation sheets from the player's own PMD Explorers
of Sky (US) ROM into pmd_sky_sprites' local data.

The player supplies the cartridge dump; nothing official ships in the
mod.  This is the offline half of the arrangement (the in-game reader
is pmd_sky_sprites/lib/romread.lua, verified byte-identical to this
parser by pmd_rom_ref.py + pmd_rom_verify.lua): it walks the NDS
filesystem, unpacks
the monster sprite bins (PKDPX where compressed), parses the SIR0/WAN
sprites, and bakes SpriteCollab-layout sheets -- N frame columns by 8
direction rows, clockwise from facing the camera -- because that art
IS this data, and the mod's directional rung already speaks it.

Formats implemented from Project Pokemon's public documentation
(SIR0, WAN/WAT, PX compression) plus empirical verification against
the ROM and SpriteCollab's AnimData (whose durations these sheets must
reproduce exactly).

Usage: pmd_rom_extract.py <rom.nds> [max_dex]
"""

import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "pmd_sky_sprites"

# anim group indices in the WAN group table (verified against
# SpriteCollab AnimData Index fields: Spearow Hover == group 4)
GROUP_WALK = 0
GROUP_HOVER = 4
# air animations only, best first; Walk is a ground gait and never used
AIR_GROUPS = [("Fly", None), ("Hover", GROUP_HOVER)]

# ------- NDS filesystem


def nitrofs_files(rom):
    fnt_off, _, fat_off, _ = struct.unpack("<IIII", rom[0x40:0x50])

    def fat(i):
        return struct.unpack("<II", rom[fat_off + i * 8: fat_off + i * 8 + 8])

    files = {}

    def walk(dir_id, prefix):
        entry_off = fnt_off + (dir_id & 0xFFF) * 8
        sub_off, first_id = struct.unpack(
            "<IH", rom[entry_off:entry_off + 6])
        p = fnt_off + sub_off
        fid = first_id
        while True:
            t = rom[p]; p += 1
            if t == 0:
                break
            name = rom[p:p + (t & 0x7F)].decode(errors="replace")
            p += t & 0x7F
            if t & 0x80:
                sub_id = struct.unpack("<H", rom[p:p + 2])[0]; p += 2
                walk(sub_id, prefix + name + "/")
            else:
                files[prefix + name] = fat(fid)
                fid += 1

    walk(0xF000, "/")
    return files


# ------- PKDPX


def pkdpx(d):
    assert d[:5] == b"PKDPX", d[:5]
    ctrl = list(d[7:16])
    out_len = struct.unpack("<I", d[16:20])[0]
    src, out = 20, bytearray()
    while len(out) < out_len and src < len(d):
        cmd = d[src]; src += 1
        for bit in range(7, -1, -1):
            if len(out) >= out_len or src >= len(d):
                break
            if cmd & (1 << bit):
                out.append(d[src]); src += 1
            else:
                cb = d[src]; src += 1
                h, n = cb >> 4, cb & 0xF
                if h in ctrl:
                    # per SkyTemple's PX spec: flags 1 and 5 shift ALL
                    # nibbles then restore nibble 0; flags 2-4 / 6-8
                    # only touch the one nibble
                    c = ctrl.index(h)
                    ny = [n] * 4
                    if c == 1:
                        ny = [n, n + 1, n + 1, n + 1]
                    elif 2 <= c <= 4:
                        ny[c - 1] = n - 1
                    elif c == 5:
                        ny = [n, n - 1, n - 1, n - 1]
                    elif c >= 6:
                        ny[c - 5] = n + 1
                    ny = [x & 0xF for x in ny]
                    out += bytes([(ny[0] << 4) | ny[1],
                                  (ny[2] << 4) | ny[3]])
                else:
                    lo = d[src]; src += 1
                    disp = 0x1000 - ((n << 8) | lo)
                    for _ in range(h + 3):
                        out.append(out[-disp])
    return bytes(out)


# ------- WAN


def u16(d, o): return struct.unpack("<H", d[o:o + 2])[0]
def s16(d, o): return struct.unpack("<h", d[o:o + 2])[0]
def u32(d, o): return struct.unpack("<I", d[o:o + 4])[0]


# OAM shape/size -> pixel dimensions
OAM_DIMS = {
    (0, 0): (8, 8), (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
    (1, 0): (16, 8), (1, 1): (32, 8), (1, 2): (32, 16), (1, 3): (64, 32),
    (2, 0): (8, 16), (2, 1): (8, 32), (2, 2): (16, 32), (2, 3): (32, 64),
}


class Wan:
    def __init__(self, d):
        self.d = d
        assert d[:4] == b"SIR0"
        wan = u32(d, 4)
        anim_info, img_info = u32(d, wan), u32(d, wan + 4)
        self.mf_ref = u32(d, anim_info)
        groups_ptr = u32(d, anim_info + 8)
        n_groups = u16(d, anim_info + 12)
        self.img_table = u32(d, img_info)
        pal_info = u32(d, img_info + 4)
        self.n_imgs = u16(d, img_info + 14)
        self.pal_colors_ptr = u32(d, pal_info)
        self.groups = []
        for g in range(n_groups):
            p = groups_ptr + g * 8
            seq_list, n_seq = u32(d, p), u32(d, p + 4)
            seqs = []
            if seq_list:
                for i in range(n_seq):
                    seqs.append(u32(d, seq_list + i * 4))
            self.groups.append(seqs)
        self._img_cache = {}

    def sequence(self, ptr):
        d, frames, p = self.d, [], ptr
        while len(frames) < 200:
            dur, flag = d[p], d[p + 1]
            mf = u16(d, p + 2)
            if dur == 0 and flag == 0 and mf == 0:
                break
            frames.append((dur, mf, s16(d, p + 4), s16(d, p + 6)))
            p += 12
        return frames

    def metaframes(self, group):
        d = self.d
        p = u32(d, self.mf_ref + group * 4)
        out = []
        last_img = 0
        while True:
            img = struct.unpack("<h", d[p:p + 2])[0]
            attr0, attr1, attr2 = u16(d, p + 4), u16(d, p + 6), u16(d, p + 8)
            if img < 0:
                img = last_img
            last_img = img
            shape = attr0 >> 14
            size = attr1 >> 14
            w, h = OAM_DIMS.get((shape, size), (8, 8))
            y = attr0 & 0xFF
            if y > 128:
                y -= 256
            x = (attr1 & 0x1FF) - 256
            hflip = bool(attr1 & 0x1000)
            vflip = bool(attr1 & 0x2000)
            is_last = bool(attr1 & 0x0800)
            pal = attr2 >> 12
            out.append((img, x, y, w, h, hflip, vflip, pal))
            p += 10
            if is_last:
                break
            if len(out) > 32:
                break
        return out

    def image_bytes(self, index):
        hit = self._img_cache.get(index)
        if hit is not None:
            return hit
        d = self.d
        p = u32(d, self.img_table + index * 4)
        out = bytearray()
        while True:
            src = u32(d, p)
            amt = u16(d, p + 4)
            if src == 0 and amt == 0:
                break
            if src == 0:
                out += bytes(amt)
            else:
                out += d[src:src + amt]
            p += 12
        self._img_cache[index] = bytes(out)
        return self._img_cache[index]

    def palette(self):
        d, colors = self.d, []
        for i in range(16):
            p = self.pal_colors_ptr + i * 4
            colors.append((d[p], d[p + 1], d[p + 2],
                           0 if i == 0 else 255))
        return colors


def draw_metaframe(canvas, cw, ch, wan, mf, cx, cy, pal):
    img, x, y, w, h, hflip, vflip, _slot = mf
    data = wan.image_bytes(img)
    tiles_w = w // 8
    for py in range(h):
        for px_ in range(w):
            tx, ty = px_ // 8, py // 8
            tile = ty * tiles_w + tx
            in_tile = (py % 8) * 8 + (px_ % 8)
            bi = tile * 32 + in_tile // 2
            if bi >= len(data):
                continue
            b = data[bi]
            v = (b & 0xF) if (in_tile % 2 == 0) else (b >> 4)
            if v == 0:
                continue
            dx = (w - 1 - px_) if hflip else px_
            dy = (h - 1 - py) if vflip else py
            ox, oy = cx + x + dx, cy + y + dy
            if 0 <= ox < cw and 0 <= oy < ch:
                canvas[oy * cw + ox] = pal[v]


def render_group(wan, group_index):
    """All 8 directions of one animation group -> (frames-per-dir,
    durations, fw, fh, rows of rendered RGBA frames)."""
    seqs = wan.groups[group_index] if group_index < len(wan.groups) else []
    if len(seqs) != 8:
        return None
    dirs = [wan.sequence(p) for p in seqs]
    n = len(dirs[0])
    if n == 0 or n > 40 or any(len(s) != n for s in dirs):
        return None
    durations = [f[0] for f in dirs[0]]
    if any(dur > 120 for dur in durations):
        return None
    # extents across every metaframe of every direction
    lo_x = lo_y = 10 ** 6
    hi_x = hi_y = -(10 ** 6)
    for s in dirs:
        for (_, mfg, xo, yo) in s:
            for (img, x, y, w, h, _, _, _) in wan.metaframes(mfg):
                lo_x = min(lo_x, x + xo)
                lo_y = min(lo_y, y + yo)
                hi_x = max(hi_x, x + xo + w)
                hi_y = max(hi_y, y + yo + h)
    fw = max(8, hi_x - lo_x)
    fh = max(8, hi_y - lo_y)
    if fw > 256 or fh > 256:
        return None
    fw += fw % 2
    fh += fh % 2
    cx, cy = -lo_x, -lo_y
    pal = wan.palette()
    rows = []
    for s in dirs:
        row = []
        for (_, mfg, xo, yo) in s:
            canvas = [(0, 0, 0, 0)] * (fw * fh)
            for mf in reversed(wan.metaframes(mfg)):
                shifted = (mf[0], mf[1] + xo, mf[2] + yo) + mf[3:]
                draw_metaframe(canvas, fw, fh, wan, shifted, cx, cy, pal)
            row.append(canvas)
        rows.append(row)
    return n, durations, fw, fh, rows


# ------- PNG


def write_png(path, w, h, rgba_rows):
    raw = b"".join(b"\x00" + bytes(v for px_ in row for v in px_)
                   for row in rgba_rows)

    def chunk(tag, body):
        c = tag + body
        return struct.pack(">I", len(body)) + c + struct.pack(
            ">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    pathlib.Path(path).write_bytes(png)


def bake_sheet(path, fw, fh, rows):
    n = len(rows[0])
    w, h = fw * n, fh * 8
    grid = [[(0, 0, 0, 0)] * w for _ in range(h)]
    for r, row in enumerate(rows):
        for c, frame in enumerate(row):
            for y in range(fh):
                for x in range(fw):
                    grid[r * fh + y][c * fw + x] = frame[y * fw + x]
    write_png(path, w, h, grid)


# ------- driver


def main():
    rom = pathlib.Path(sys.argv[1]).read_bytes()
    max_dex = int(sys.argv[2]) if len(sys.argv) > 2 else 251
    files = nitrofs_files(rom)

    def pack_entry(name, idx):
        s, e = files[name]
        pack = rom[s:e]
        count = u32(pack, 4)
        if idx >= count:
            return None
        off, size = struct.unpack("<II", pack[8 + idx * 8: 16 + idx * 8])
        if size == 0:
            return None
        d = pack[off:off + size]
        if d[:5] == b"PKDPX":
            d = pkdpx(d)
        return d if d[:4] == b"SIR0" else None

    (ROOT / "sprites").mkdir(parents=True, exist_ok=True)
    (ROOT / "data").mkdir(parents=True, exist_ok=True)
    rows_lua, baked = [], 0
    for dex in range(1, max_dex + 1):
        got = None
        for name, group in AIR_GROUPS:
            if group is None:
                continue
            d = pack_entry("/MONSTER/m_attack.bin", dex)
            if not d:
                continue
            try:
                r = render_group(Wan(d), group)
            except Exception:
                r = None
            if r:
                got = (name,) + r
                break
        if not got:
            continue
        name, n, durations, fw, fh, rows = got
        file = "%04d.png" % dex
        bake_sheet(ROOT / "sprites" / file, fw, fh, rows)
        durs = ", ".join(str(x) for x in durations)
        rows_lua.append(
            '  [%d] = { file = "%s", anim = "%s", fw = %d, fh = %d, '
            "frames = %d, durations = { %s } }," %
            (dex, file, name, fw, fh, n, durs))
        baked += 1
    lua = ["-- generated by scripts/pmd_rom_extract.py from the",
           "-- PLAYER'S OWN Explorers of Sky ROM.  Local only: this",
           "-- data is derived from a cartridge the player supplies",
           "-- and must never be committed or shipped.",
           "return {"] + rows_lua + ["}"]
    (ROOT / "data" / "sheets.lua").write_text("\n".join(lua) + "\n")
    print("baked %d species from the ROM" % baked)


if __name__ == "__main__":
    main()
