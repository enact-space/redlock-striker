# Redlock Striker (working title)

A portrait lane-shooter spin-off of [Redlock](https://github.com/enact-space/redlock), built in Godot 4.3 (GL Compatibility, phone-first, web demo).

Your squad runs up a floating Redlock training pitch kicking footballs on its own. Drag left and right to steer.
Holographic keepers march down at you, crate stacks at the lane edges give rewards when you kick their number down
to zero, and every stage ends with a giant holo keeper while the Director watches from the big screen.

## What's in the prototype

- `scripts/main.gd`: world, camera, HUD, stage timeline, balls (one MultiMesh), collisions, rewards, boss, Spirit Shot.
- `scripts/holo_keeper.gd`: holographic keeper enemies (grunt, brute, boss), glowing scanline shader.
- `scripts/reward_gate.gd`: crate stacks with a hit counter and a reward (+strikers, +1 ball, power, rapid kicks, curve, spirit, a second hero).
- `scripts/striker.gd`: squad members. STAND-IN figures until the real models are in: `use_model()` swaps one for a GLB
  (the game loads `res://assets/characters/hiyori.glb` for Hiyori when the file exists).

Rewards: stage 1 always offers the second hero (Kasumi if you lead with Hiyori, and the other way round).
Spirit Shot fills from knockouts; it is a big ball that clears its column and takes 30% off a boss.

## Debug flags

`godot -- --auto` plays itself (steers to crates, then crowds). Also `--stage=N`, `--boss` (jump to the boss with a
bigger squad), `--spirit`, `--shot=path.png --at=secs` (screenshot), `--quit=secs` (prints a one-line summary).

## Web demo

`GODOT=/path/to/godot4.3 tools/web/build.sh N` exports the web build and lays out `build/page/` for publishing
(wasm and pck split into parts under the per-file size limit, page shell from `tools/web/index.html`).
