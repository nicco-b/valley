# Creature asset contract (Blender → Godot)

What a character .blend must satisfy to drop into the game. The star hound
(`star_hound.blend`) is the worked example of all of it.

## Space & scale
- Real meters, origin at ground level between the feet.
- **Face -Y in Blender** (Z up). The glTF exporter turns that into +Z
  forward in Godot, which is what `player.gd` / NPC facing math assume
  (identity transform, `atan2(dir.x, dir.z)` yaw).
- Player-scale reference: the hound is ~1.0m at the back, ~1.5m total;
  the humanoid NPCs are ~1.7m. Keep new bipeds in that family.

## Rig & clips
- One armature, one mesh (join parts; per-part rigid weights are fine and
  suit the toy-like style — see the hound's bead tail).
- 24 fps. Clip names the game resolves (`player.gd _ANIM_FALLBACKS`):
  `Idle`, `Walking`, `Running` (loops — first key == last key),
  `Sitting`, `Jump` (one-shots — the game holds their final frame).
  A subset degrades gracefully via the fallback map.
- Stash every action in its own (muted) NLA track so the exporter sees
  them all; `use_fake_user` on actions so they survive saves.

## Materials
- Flat Principled per color, roughness 1.0. Painterly depth (soft-light
  mottle + paper grain + fresnel edge-dark) is a node tree on top — keep
  the flat color in an RGB node labeled `BASE` so the exporter script can
  flatten it (glTF can't take the tree; the .glb ships flat colors).
- Patterns that must read at distance (stars, ticks) are skinned
  geometry decals, not textures.

## Export
- Run the embedded `export_glb.py` (Text Editor ▸ Alt+P) — it flattens
  `BASE`-labeled colors, exports the **Build** collection to
  `assets/models/creatures/<name>.glb` with per-action animations, and
  relinks the painterly trees. Never export the Reference collection.
- Then `./scripts/test.sh` (Godot reimports changed sources on its own).

## Working files
- `<name>_wip.blend` while modeling; reference paintings live in
  `assets/blender/reference/` (git-tracked, `.gdignore`d so Godot
  ignores the folder).
- `.blend1` backups are git-ignored.
- An AI session can take a finished sculpt through rig → clips → export;
  the hound's rig (3-bone legs, chained tail) is the template.
