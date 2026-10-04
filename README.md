# Smarter Walls

A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme. Dragged walls go in a
straight line at any angle and flow around buildings, trees and rocks instead of turning red;
crenellations follow the wall they are dragged along. Building a wall over damaged stairs puts
the stairs back at their old height, and over a damaged crenellation repairs the
crenellation (only an intact one is turned into wall).

What the module does, in plain English, is in `module/locale/description-en.md`.

## What is in here

| Folder | |
|---|---|
| `module/` | the module itself - this is the source of truth, edited in place |
| `bench/` | the emulator bench: the module's own Lua runs against the real exe image, its assembly is assembled with UCP's own fasm.dll and then executed together with the game's wall code |
| `tools/publish.py` | copies `module/` into the game's module folder under a new version |

## Working on it

1. Edit under `module/`.
2. Run the bench until it is green: `python bench/test_sw.py` (routes in an open field, around
   a building, preview = wall = cost, crenellations along a bent wall, the stairs and
   crenellation repairs, and the damage hooks), on both executables and five settings mixes.
3. `python tools/publish.py --bump` - raises the last version slot and copies the module to
   `ucp/modules/smarter-walls-<version>`.
4. In the UCP GUI press F5, then apply. `ucp-config.yml` is never edited by hand.
5. Commit and tag: `git commit -am "<version> - <what changed>" && git tag v<version>`.

The bench needs Python with `lupa`, `capstone`, `pefile` and `keystone-engine`, and a 32-bit
PowerShell for fasm.dll; it reads the executables from the game folder named in `shc.py`.
