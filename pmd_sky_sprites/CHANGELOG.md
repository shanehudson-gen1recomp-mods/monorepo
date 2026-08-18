# Changelog

## 0.2.0

- The player's own cartridge fills the gaps: drop an Explorers of Sky
  (US) .nds beside main.lua and lib/romread.lua reads the official
  in-air sheets out of it at resolve time (NitroFS, PKDPX, SIR0/WAN),
  baked in memory and served through the Assets.image choke point.
  Community sheets still win where they exist; nothing official ships
  or is written to disk. An IMPORT PMD toggle in the mod's settings
  (on by default) gates the cartridge rung and takes effect live.
- The reader is verified byte-identical to the offline extractor on a
  real ROM by scripts/pmd_rom_ref.py + scripts/pmd_rom_verify.lua.
- PX decompression fixed against SkyTemple's spec: two of the nine
  control-flag nibble patterns decoded one too high, corrupting the
  occasional metaframe index and animation timing.
- WAN group indices mean different animations per species (slot 4 is
  Spearow's Hover but Pidgeot's FlapAround tumble -- which is why the
  Pidgey line spun instead of flapping), so data/anims.lua, baked
  from SpriteCollab AnimData by scripts/pmd_animdata.py, names each
  species' air group: Fly, else Hover, else FlapAround masked to its
  two clean flap columns, else the Walk cycle (in PMD a flyer flies
  and a floater floats in its Walk).  Walk lives in a different pack,
  so the reader now tries all three /MONSTER bins.  Coverage: all 251
  species.
- A missing data/sheets.lua no longer disables the mod; the cartridge
  alone can dress the sky.

## 0.1.0

- First release: SpriteCollab community sheets as sky-family sprite
  sources (Wild Skies flyers, Free Fly mounts), 8 direction rows per
  species, dex-keyed with the shared resolver's canonical-dex guard.
- Official Spike Chunsoft sheets are excluded at bake time; only
  community-credited CC BY-NC art ships. Coverage grows as the collab
  redraws species; the bake script re-pulls in one command.
