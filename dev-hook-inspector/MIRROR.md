**What it does**: once installed, the START menu gains a HOOKS entry
listing every installed mod's public surface: the exports other mods
can call through `mod.find(id)` and the events they broadcast, each
with a description pulled from the mod's own source. Every pick is
also printed to the console, untruncated and copyable.

**Why**: gen1recomp mods integrate through exports and events, but
nothing in the game shows what a given mod actually offers; wiring
mods together means reading their source. The inspector answers that
in-game, against what is really installed and running, and needs no
cooperation from the inspected mods: exports are enumerated live off
the loader, events and descriptions are read from each mod's own code.
Built for mod authors; regular players don't need it.
