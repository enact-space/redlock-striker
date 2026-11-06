# Redlock Striker (working title)

A portrait lane-shooter spin-off of [Redlock](https://github.com/enact-space/redlock), built in Godot 4.3 (GL Compatibility, phone-first, web demo).

A fixed steep camera looks down a floating Redlock bridge. Your squad stands near the bottom and kicks footballs
nonstop; drag left and right to aim it. Holographic keepers pour down from the gate at the far end and cost you
strikers when they reach the squad. Two spiral racks flank the far end: shoot the bottom crate's number down to zero
for its reward. The right rack gives recruits (+1 ... +99, and the second captain early on), the left rack gives boot
upgrades (more damage, faster kicks, new kit colours). A giant holo keeper with a big health number walks down every
so often.

## Code

- `scripts/main.gd`: world, camera, HUD, keeper stream, balls, crowd, bosses, rewards. Keepers, balls and the crowd
  are MultiMeshes so the squad can reach 300.
- `scripts/tower.gd`: a spiral rack of reward crates.
- `scripts/meshes.gd`: merged one-draw-call meshes (trainee, holo keeper).
- `scripts/holo_keeper.gd`: the giant holo keeper boss.
- `scripts/striker.gd`: the captains (Hiyori, Kasumi). Uses the real models in `assets/characters/` (idle and run
  clips), with a box stand-in only if a file is missing.

## Character models

`assets/characters/hiyori.glb` (Hiyori Fujisaki v06) and `kasumi.glb` (Kasumi Tsukishiro v01) are phone-sized copies
of the handoff GLBs: `python3 -I tools/models/shrink_glb.py IN.glb OUT.glb 1024` scales every texture down to 1024 px
and leaves the mesh, rig and animations untouched. The full-size originals stay on Drive.

## Debug flags

`godot -- --auto` plays itself (handles close keepers, otherwise works the racks). Also `--t=secs`, `--crowd=N`,
`--tier=N`, `--closeup` (camera next to the captains), `--shot=path.png --at=secs` (screenshot), `--quit=secs`
(prints a one-line summary).

## Web demo

`GODOT=/path/to/godot4.3 tools/web/build.sh N` exports the web build and lays out `build/page/` for publishing
(wasm and pck split into parts under the per-file size limit, page shell from `tools/web/index.html`).
