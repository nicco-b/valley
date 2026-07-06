# The Blender terrain pipeline (the Toolkit)

Open the world in Blender, sculpt it, set-dress it with kit objects,
and write both back in the game's own formats. The elevation guide
stays the source of truth; the in-game bake (fractal relief + thermal
talus + hydraulic erosion) keeps authoring believable detail on top of
whatever is sculpted here. **You are editing the landform, not the
final terrain** — sculpt composition, let the erosion do texture.

## Commands (from the repo root)

```sh
# 1. Build the .blend from the current world (guide + placements):
blender -b --python assets/blender/terrain/valley_terrain.py -- import

# 2. Open it, sculpt / place, save:
blender assets/blender/terrain/valley_map.blend

# 3. Export back to the game (or run the script in the Scripting tab —
#    it auto-detects export when the terrain object exists):
blender -b assets/blender/terrain/valley_map.blend \
    --python assets/blender/terrain/valley_terrain.py -- export

# 4. Rebake and (if running) watch the world reshape under you:
godot --headless --path . -s res://tests/bake_world.gd
```

Self-check (run after editing the script): `blender -b --python
assets/blender/terrain/valley_terrain.py -- test`

The `.blend` is derived local state (gitignored) — regenerate it any
time with step 1. Commit what the export writes: the guide EXR and
`data/cells/*.json`.

## Conventions

- **Scale 1:10.** 1 Blender unit = 10 m; the 16.4 km world is a
  ~1638-unit plane. Heights are true to scale.
- **Axes:** Blender +X = world +X · Blender **+Y = world −Z** (north
  is up in top view) · Blender Z = up.
- **Terrain** is the `ValleyTerrain` object: one vertex per guide
  pixel (1024²), heights baked into the mesh. Sculpt it directly.
  Transforms are locked — sculpt, don't move the object.
- **Placements** live in the `Placements` collection. Object name =
  kit id (`.001` suffixes are stripped): `rock_large`, `rock_med`,
  `tree_silly`, `tree_palm`, `shrub`. Rotate around Z (= in-game yaw),
  scale uniformly. Duplicate (Alt+D) to place more. Export writes them
  as cell records with `snap: true`, so they seat on the real baked
  ground — your Blender terrain is the guide, and the bake adds
  relief, so never trust exact Z here; trust XZ and yaw.
- New kit ids: add the scene to `game/world/kit.gd` ENTRIES and a
  proxy shape to `KIT_PROXY` in `valley_terrain.py`.

## "It looks low-res"

It's showing you the **guide** — the 16 m/pixel landform layer. The
detail you know from the game (drainage grooves, talus, coast
raggedness, per-cell relief) is *baked on top* by the erosion pass
after every export, then the cell mesher adds its own near-field
noise. You're sculpting the skeleton; the bake regrows the skin.
Two knobs if you want more anyway:

- `-- import --res 2048` builds the sculpt mesh at 8 m/vertex
  (bilinear upsample — no new information, but finer brush control;
  export writes the guide at the mesh's res and the bake accepts any
  width). 2048² ≈ 4M verts: still sculptable, slower to import.
- The real global-fidelity knob is the bake's `out_res` in
  `data/world/guide.json` (2048 today = 8 m/px baked). Raising it is
  a map-pipeline decision (bake cost/memory ×4 per step) — kitchen
  table, not a Blender-side setting.

## Sculpting notes

- **Turn OFF X-symmetry** (Blender sculpt default) — the archipelago
  is not symmetric.
- Overhangs cannot survive: the export ray-samples the surface from
  above (one height per point — the heightfield law). Anything folded
  over flattens. Verticality is the cliff kit's job.
- The guide is 16 m/pixel: features narrower than ~2 pixels won't
  survive the trip. Ridgelines, valleys, coasts, plateaus — yes;
  individual boulders — that's a placement, not a sculpt.
- Cells emptied of placements in Blender are NOT deleted on disk
  (safety) — remove stale `data/cells/cell_X_Y.json` by hand.
- The erosion bake reshapes drainage after every guide change; if a
  placed object mattered (a shrine on a ridge), check it in-game after
  the rebake.
