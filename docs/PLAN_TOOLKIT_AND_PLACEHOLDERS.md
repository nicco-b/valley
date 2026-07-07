# Plan — Toolkit build-out + the placeholder asset drop

*Written 2026-07-06 for a fresh session to execute. Context: Nicco played
with the Toolkit ("its pretty nice… i love our editor i think we can just
make it way better") and has a full synthetic placeholder drop ready.
Read CLAUDE.md and docs/STATUS.md first, as always. The DECISIONS
2026-07-05 Toolkit priority order (3–6) is folded in below, reordered
where the asset drop changes the economics.*

## Inputs

**The asset drop (on disk, not yet in repo):**
`/Users/nicco/Downloads/files-2/valley-placeholders/`
- 258 billboard PNGs across 86 slots → `assets/paintings/…`
- 345 static GLBs across 112 slots → `assets/models/…` (trees, rocks,
  cliffs, shrubs, cacti, props, arch, landmarks, items, chars, wildlife)
- Every slot has a `.card.json`: `{slot, class, variants, files, status:
  "placeholder-synth", collision, clips, gated}` — the one-asset =
  files + card contract. Gated rows (UND/glow/hero) flagged `gated: true`.
- Generators in `tools/` (gen_billboards.py, gen_meshes.py) — copy into
  the repo too (`tools/placeholders/`) so slots can be regenerated.
- Honest limits (from its PLACEHOLDERS.md): meshes are STATIC — no rigs,
  no clips; humanoid/wildlife are silhouette stand-ins; -col nodes are
  convex hulls; foliage sheets are 2×2 clump grids the loader must cut.
- Contact sheets: contact_billboards.png / contact_meshes.png.

**Standing decisions that bind this work:**
- Toolkit is dev-only (is_debug_build) but lives in the one app forever.
- Every placeholder stays labeled with its replacement path (the card's
  `status` field IS that label now — flip to retire).
- Full-treatment asset counts (memory: full-treatment-assets): never
  strip variants to "save space"; the density is the point.
- Landform authoring stays FILE-driven for whole-world strokes; the live
  pens are for local edits. Do NOT re-add in-map generation drawing.
- Map workflow ruling (2026-07-06): get the landform ~90% right → place
  → local-polish only. No sacred final map, but no moving mountains
  under dressed areas.

## Phase 0 — land the drop (do FIRST, forces the LFS decision)

1. **Git LFS, finally.** ~600 binaries is the moment. The .gitattributes
   patterns were written 2026-07-04 but never committed (git-lfs wasn't
   installed). Install git-lfs on THIS machine, commit the attributes
   (cover *.glb, *.png under assets/, *.exr), THEN copy the drop in.
   Coordinate with Nicco before any history rewrite — none is required
   for this; new files just start tracked. If LFS can't be installed
   today, ask Nicco whether to proceed raw (repo is private; his call).
2. Copy `assets/paintings/` + `assets/models/` + PLACEHOLDERS.md into the
   repo tree (same paths); generators → `tools/placeholders/`.
3. Import pass: `godot --headless --import` — expect a long first import
   (345 glbs). Add/verify sensible import defaults for billboard PNGs
   (no mipmaps? repeat off — match how current billboard PNGs import).
4. `./scripts/test.sh` green before the commit. Push, then ff Nicco's
   primary checkout (memory: main-only-no-branches) and REBAKE/import
   there too (pipeline-changes rule).

## Phase 1 — cards become the source of truth (was DECISIONS #3)

The drop makes this urgent: 112 mesh slots cannot live in Kit.ENTRIES.

1. **Card loader** in Records: scan `assets/**/**.card.json` (schema:
   slot/class/variants/files/status/gated), validated. Toolkit dashboard
   counts real vs placeholder-synth per category (the PLACEHOLDERS.md
   contract expects exactly this).
2. **Kit palette from cards**: placeable palette generated from mesh
   cards (class gltf_mesh, not gated) with category grouping (trees,
   rocks, props…). Kit.ENTRIES survives only for non-card entries until
   migrated, then dies. Placement writes the same cell records as today.
3. **Variant handling**: placing a slot picks a variant (deterministic
   seed by position, or explicit in the Toolkit UI). Cell records store
   the resolved file, not the slot, so retiring a placeholder never
   moves placed objects.
4. **Flora species slots**: `data/flora/*.json` stage-art slots point at
   the new billboard paintings where a matching slot exists (blooms,
   foliage, ground covers per biome). The 2×2 clump sheets need the
   loader to cut UV quadrants — smallest possible change to the scatter
   billboard material.
5. Wire the ground-cover sets (`paintings/ground/<biome>/`) to the 8
   biomes; sky strips and horizon paintings are separate consumers —
   note them in the ledger, wire only if cheap (sky is a shader today).

## Phase 2 — the sculpting feel (pens + undo)

1. **Cross-pen undo/history** (DECISIONS #6 pulled early): generalize
   sculpt's Z-undo into an undo stack covering sculpt, terrain-guide
   strokes, biome paints, river carves, and placement (add/delete/move).
   Per-tool memento; one keybind (Z / Shift+Z).
2. Brush ring projected on terrain (radius/strength preview),
   scroll-wheel radius, falloff curves (sharp/soft), Shift=smooth.
3. **Set-height eyedropper** for the sculpt pen (sample height, paint it
   — plateaus and terraces).

## Phase 3 — placement tools (DECISIONS #4)

1. Multi-select: click-drag box + shift-click; group move/rotate/delete.
2. Alt-drag duplicate; snap-to-ground; align-to-normal toggle;
   random-yaw on place.
3. **Scatter brush**: paint from a card slot with density/jitter radius,
   writing ordinary cell records (erasable, undoable). This is how the
   345 meshes actually get USED at full-treatment density.
4. Eraser (record delete under brush).

## Phase 4 — editor quality-of-life

1. Sim-freeze toggle + eager saves (Toolkit checklist stragglers).
2. Camera bookmarks (Ctrl+num set, num jump).
3. World panel (O) grows WRITE knobs where systems have them (the
   "systems it can't steer are debt" rule).
4. Live rule-card editing (DECISIONS #5) — now meaningful because cards
   exist; start with scatter defaults on mesh cards.

## Ground rules for the executing session

- `./scripts/test.sh` before every commit; soak untouched by all of this
  (presentation + editor + data only — if a phase moves the soak
  fingerprint, something is wrong; stop and investigate).
- Commit per phase or finer; push; ff Nicco's checkout after every push.
- Every new script: `##` doc comment + system name tag (these are all
  **the Toolkit** except the card loader, which is **the Chronicle**).
- New systems ship Toolkit observability (summary()) — the card
  dashboard IS Phase 1's.
- Hand-written .tscn gotchas, reimport.sh, and the rest: CLAUDE.md.
- Nicco's uncommitted authored files may exist in his primary checkout
  (pen rivers, cell placements, painted maps) — never clobber; triage.

## Open questions to surface to Nicco early (don't block Phase 0)

- LFS: install now on this machine? (Plan assumes yes.) Second machine
  install before he next pulls there.
- Palette UI shape once 112 slots exist: categories + search? thumbnails
  (render-to-texture contact cards)? Cheap first pass: category tabs +
  the existing contact sheets as reference.
- Wildlife/char stand-ins are static silhouettes — placeable as props,
  but do NOT wire them as agent bodies (no clips; the clip-name contract
  stays open in the ledger).
