Third-party mods this release was run alongside, with the exact
versions used. Later versions of these mods may change behavior; if a
combo misbehaves, check the version you have against this list first.

| Mod | Version tested | Notes |
|---|---|---|
| [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) | 1.6.2 | built-in scene detection plus the adapter composing both battlers into its billboard textures |
| Battle Art voxel fork | 1.7.6 | same scene detection path as Dramatic Shape |
| Gen1 Modern UI (`gen1_modern_ui`) | 0.8.3 | its battle cards name the right Pokémon through the slot borrow |
| [Crystal 251](https://github.com/Deftones565/gen1recomp-mod-crystal-251) (`CRYSTAL_251`) | 0.10.1 | compatibility developed against its source and covered by the headless suite, not yet play-tested. Its class-level battle patches (executeAction, TrainerAI, Status.residual, the battle.damage hook) all sit on paths our turn loop calls, partner battlers are announced for its per-battler stat attach, and its solitary legends stay 1v1. Known limit: its per-turn wild flee rolls do not run inside a double |
