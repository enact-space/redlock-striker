# Redlock Striker (working title)

A portrait lane-shooter spin-off of [Redlock](https://github.com/enact-space/redlock), built in Godot 4.3 (GL Compatibility, phone-first, web demo).

A fixed camera behind the squad looks up a long floating Redlock bridge. You pick Hiyori or Kasumi, and every
squad member is a clone of her. The squad stands at the near end and kicks footballs straight up the bridge
nonstop; drag left and right to pick a lane. Holographic keepers march straight down the middle (they never turn
towards you): walking into the squad costs clones, and so does each one that slips past. Two rows of low walls line the edge lanes: kick the front wall's
number down to zero and it smashes, its upgrade flies to the squad and the walls behind slide forward (the little
grey walls hold nothing). The
right row gives clones: runs of cheap +1 walls first, bigger prizes further up (+2 ... +99), the left row gives boot upgrades (more damage, faster kicks, a new disc colour
under the squad).

Levels: each level is a fresh run. A bar under the level name fills until the level's giant holo keeper walks
out; beat it to clear the level and unlock the next. Later levels have tougher, more numerous keepers and a bigger
boss, and you start them with two clones plus one per two levels behind you (up to 12). The title screen lets you pick any
unlocked level; progress is saved in `user://striker_save.json`. A near-perfect bot (`--auto --level=N`) clears
levels 1-16 and fails around 20.

## Code

- `scripts/main.gd`: world, camera, HUD, keeper stream, balls, crowd, bosses, rewards. Keepers, balls and the crowd
  are MultiMeshes so the squad can reach 300.
- `scripts/reward_row.gd`: a row of smashable walls (plain or upgrade).
- `scripts/meshes.gd`: merged one-draw-call meshes (holo keeper).
- `scripts/holo_keeper.gd`: the giant holo keeper boss.
- `scripts/striker.gd`: the squad leader, the full animated model. Kicks on the spot (the `kick` clip, looped from
  the last stride to the follow-through) and runs while the squad slides.

## Character models

`assets/characters/hiyori.glb` (Hiyori Fujisaki v06) and `kasumi.glb` (Kasumi Tsukishiro v01) are phone-sized copies
of the handoff GLBs: `python3 -I tools/models/shrink_glb.py IN.glb OUT.glb 1024` scales every texture down to 1024 px
and leaves the mesh, rig and animations untouched. The full-size originals stay on Drive.

The clones are baked from the same models: `tools/models/bake_clone.gd` poses the model in a clip, skins it on the
CPU and simplifies it to about 1,600 triangles. `assets/characters/<who>_kick_0..5.res` are six frames of the kick that
the crowd plays as a flipbook (each clone at its own offset), so hundreds of clones stay one draw call per frame.

The football clips (`kick`, `kick_running`, `pass`) come from the rigged Medium Body (same skeleton as Hiyori and
Kasumi): `tools/models/extract_clips.gd` copies them, without root travel, into `assets/characters/football_clips.res`.

## Debug flags

`godot -- --auto` plays itself (handles close keepers, otherwise works the reward rows). Also `--t=secs`, `--crowd=N`,
`--level=N`, `--cleared` (show the cleared screen), `--tier=N`, `--closeup` (camera next to the squad), `--shot=path.png --at=secs` (screenshot), `--quit=secs`
(prints a one-line summary).

## Web demo

`GODOT=/path/to/godot4.3 tools/web/build.sh N` exports the web build and lays out `build/page/` for publishing
(wasm and pck split into parts under the per-file size limit, page shell from `tools/web/index.html`).

Fast balance runs: `godot --fixed-fps 60 --disable-vsync -- --auto --quit=120`.
