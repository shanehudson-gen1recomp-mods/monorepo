#!/usr/bin/env python3
"""Bake PMDCollab SpriteCollab sheets into pmd_sky_sprites.

Fetches, for each national dex number, the species' AnimData.xml and the
best in-air animation sheet (Fly, then Hover), and writes:

  pmd_sky_sprites/sprites/NNNN.png       the sheet, verbatim
  pmd_sky_sprites/data/sheets.lua        dex -> geometry + durations
  pmd_sky_sprites/CREDITS.md             per-species SpriteCollab credits
  pmd_sky_sprites/LICENSE-SPRITES.md     CC BY-NC 4.0 pointer

Sheets are N frame columns x 8 direction rows (clockwise from facing
the camera), uniform frames, per AnimData.  Usage: scripts/pmd_pack.py
[max_dex] [--include-official]  (default 251, community art only).

--include-official is for LOCAL testing only: it also bakes the
official Spike Chunsoft sheets, which must never ship -- do not commit
a pack built with it.
"""

import concurrent.futures
import pathlib
import re
import sys
import urllib.request

RAW = "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite"
ROOT = pathlib.Path(__file__).resolve().parent.parent / "pmd_sky_sprites"
# Air animations only: a PMD Walk cycle is a ground gait, and a mount
# strutting in mid-air is worse than the generic bird it replaces.
# FlapAround is a TUMBLE, but its first two columns are an upright
# wings-up/wings-down pair synchronized across the direction rows --
# a clean flap loop once the rest of the sheet is masked off (the
# frame subset below, honored by the shared resolver's directional
# draw).  The Pidgey line ships FlapAround where it has no Fly/Hover.
PREFERENCE = ["Fly", "Hover", "FlapAround"]
FRAME_SUBSETS = {"FlapAround": [1, 2]}


def fetch(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return r.read()
    except Exception:
        return None


def anims_of(xml):
    out = {}
    for m in re.finditer(rb"<Anim>(.*?)</Anim>", xml, re.S):
        a = m.group(1)
        name = re.search(rb"<Name>(.*?)</Name>", a)
        fw = re.search(rb"<FrameWidth>(\d+)</FrameWidth>", a)
        fh = re.search(rb"<FrameHeight>(\d+)</FrameHeight>", a)
        durs = re.findall(rb"<Duration>(\d+)</Duration>", a)
        copy = re.search(rb"<CopyOf>(.*?)</CopyOf>", a)
        if name:
            out[name.group(1).decode()] = {
                "fw": fw and int(fw.group(1)),
                "fh": fh and int(fh.group(1)),
                "durations": [int(d) for d in durs],
                "copy": copy and copy.group(1).decode(),
            }
    return out


def community_anims(credits_text):
    """Animations whose CURRENT credit is a community contributor.

    credits.txt rows: date, contributor, CUR/OLD, license, anim CSV.
    CHUNSOFT rows are the official Spike Chunsoft sprites imported from
    the PMD games -- excluded outright: this pack ships community art
    only.  Later rows win, so a community redraw of an official anim
    counts and an official revision over a community sheet does not.
    """
    latest = {}
    for line in credits_text.splitlines():
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        contributor, anims_csv = parts[1].strip(), parts[4]
        official = contributor.upper() == "CHUNSOFT"
        for anim in anims_csv.split(","):
            anim = anim.strip()
            if anim:
                latest[anim] = not official
    return {a for a, communal in latest.items() if communal}


def bake(dex):
    nnnn = "%04d" % dex
    xml = fetch(f"{RAW}/{nnnn}/AnimData.xml")
    if not xml:
        return dex, None, None
    credits_raw = (fetch(f"{RAW}/{nnnn}/credits.txt") or b"").decode(
        errors="replace")
    allowed = community_anims(credits_raw)
    anims = anims_of(xml)
    for want in PREFERENCE:
        a = anims.get(want)
        if not a:
            continue
        # CopyOf redirects to another anim's sheet (e.g. Fly copying Walk)
        sheet_name = want
        seen = set()
        while a and a.get("copy") and a["copy"] not in seen:
            seen.add(sheet_name)
            sheet_name = a["copy"]
            a = anims.get(sheet_name) or a
        if not (a.get("fw") and a.get("fh") and a["durations"]):
            continue
        # the SHEET being shipped is what must be community art
        if sheet_name not in allowed and not INCLUDE_OFFICIAL:
            continue
        png = fetch(f"{RAW}/{nnnn}/{sheet_name}-Anim.png")
        if not png:
            continue
        (ROOT / "sprites").mkdir(parents=True, exist_ok=True)
        (ROOT / "sprites" / (nnnn + ".png")).write_bytes(png)
        rec = {
            "file": nnnn + ".png",
            "anim": want,
            "sheet": sheet_name,
            "fw": a["fw"],
            "fh": a["fh"],
            "frames": len(a["durations"]),
            "durations": a["durations"],
        }
        subset = FRAME_SUBSETS.get(sheet_name)
        if subset:
            rec["subset"] = subset
        return dex, rec, credits_raw.strip()
    return dex, None, None


INCLUDE_OFFICIAL = False


def main():
    global INCLUDE_OFFICIAL
    args = [a for a in sys.argv[1:] if a != "--include-official"]
    INCLUDE_OFFICIAL = "--include-official" in sys.argv
    max_dex = int(args[0]) if args else 251
    rows, credits = {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        for dex, rec, cred in pool.map(bake, range(1, max_dex + 1)):
            if rec:
                rows[dex] = rec
                if cred:
                    credits[dex] = cred
    lua = ["-- generated by scripts/pmd_pack.py from PMDCollab/SpriteCollab",
           "-- CC BY-NC 4.0 with attribution; see CREDITS.md",
           "return {"]
    for dex in sorted(rows):
        r = rows[dex]
        durs = ", ".join(str(d) for d in r["durations"])
        subset = ""
        if r.get("subset"):
            subset = ", subset = { %s }" % ", ".join(
                str(i) for i in r["subset"])
        lua.append(
            '  [%d] = { file = "%s", anim = "%s", fw = %d, fh = %d, '
            "frames = %d, durations = { %s }%s }," %
            (dex, r["file"], r["anim"], r["fw"], r["fh"], r["frames"],
             durs, subset))
    lua.append("}")
    (ROOT / "data").mkdir(parents=True, exist_ok=True)
    (ROOT / "data" / "sheets.lua").write_text("\n".join(lua) + "\n")

    lines = ["# Sprite credits",
             "",
             "Every sheet in sprites/ comes from the community-run",
             "[PMDCollab SpriteCollab](https://github.com/PMDCollab/SpriteCollab),",
             "licensed CC BY-NC 4.0. Per-species contributor credits, as",
             "recorded by the collab at bake time:", ""]
    for dex in sorted(credits):
        lines.append("## %04d" % dex)
        lines.append("```")
        lines.append(credits[dex])
        lines.append("```")
    (ROOT / "CREDITS.md").write_text("\n".join(lines) + "\n")
    (ROOT / "LICENSE-SPRITES.md").write_text(
        "The images under sprites/ are from PMDCollab SpriteCollab\n"
        "(https://github.com/PMDCollab/SpriteCollab) and are licensed\n"
        "Creative Commons Attribution-NonCommercial 4.0 International\n"
        "(CC BY-NC 4.0). See CREDITS.md for per-species contributors.\n"
        "This mod is free and non-commercial.\n")
    print("baked %d species (%d with credits)" % (len(rows), len(credits)))


if __name__ == "__main__":
    main()
