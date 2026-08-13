Gen 2 (Gold) support in 1.9.0 is covered by the headless suite and
`modkit gen2check`, plus several in-game Gold rounds during
development (spawning, levels, seams, sprites, battles); a full
pre-release Gold pass is still recommended.

Third-party mods this release was run alongside, with the exact
versions used. Later versions of these mods may change behavior; if a
combo misbehaves, check the version you have against this list first.

| Mod | Version tested | Notes |
|---|---|---|
| [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) | 1.6.2 | flyers billboard in the diorama with real altitude, rooftop perching on its building volumes |
| [Wilds of Kanto](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters) (`overworld_wild_spawns`) | 1.12.1 | its levitates art dresses the birds; the sky tick heals if its follower engine resets the update hook |
| Overworld Wild Encounters (`overworld_encounters`) | 0.0.5 | its roamers own the ground, this mod owns the air, battles never cross |
| Gen1 Modern UI (`gen1_modern_ui`) | 0.8.3 | wild_skies 1.6.1 broke its modern menus (our old overworld draw hook tripped its renderer check); fixed in 1.6.2, also update free_fly to 1.5.2 if installed |
| [Crystal 251](https://github.com/Deftones565/gen1recomp-mod-crystal-251) (`CRYSTAL_251`) | 0.10.1 | compatibility developed against its source and covered by the headless suite (derived pools, night ecology); not yet play-tested in game |
