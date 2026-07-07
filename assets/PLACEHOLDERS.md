# Placeholder drop — synth assets for every open manifest slot
*Generated 2026-07-06 from ASSETS manifest rev.3. Status everywhere: `placeholder-synth`.*

## What this is
Every open Part A + Part B line item filled with a procedural placeholder in the
concept paintings' language (palette sampled from the three concepts: teal segment
stalks, gold starbursts w/ pink cores, laminated striped mounds, red-sun dusk,
starfield navy, paper grain). Slots marked ✅ in the manifest were SKIPPED (real
art exists). The ⚠ dry_tuft SVG is retired by a painted-grain PNG.

- Part A billboards: 258 PNGs across 86 slots → assets/paintings/
- Part B meshes:     345 GLBs across 112 slots → assets/models/
- Every asset has its .card.json (per the one-asset = files + card contract),
  with `"status": "placeholder-synth"` so the dashboard can count real vs synth.
- Gated rows (UND / glow / hero) are generated but flagged `"gated": true` —
  they exist so the loaders and lineup scene work, not as fiction commitments.

## Honest limits
- Meshes are static. NO rigs, NO animation clips — humanoid_base and wildlife
  are silhouette stand-ins only. The clip-name contract cannot be satisfied
  synthetically; those rows stay open in the ledger.
- -col nodes are convex hulls (fine for placeholder physics, generous on arches).
- Foliage card sheets are 2×2 clump grids; UV card-cutting is up to the loader.
- Sky strips are 512×1536 verticals; dusk strip bakes the red sun in.

## Retiring a slot
Paint/model the real asset → drop into the same file slot → flip card status.
Nothing else changes; seeds and generators live in tools/ for regeneration.
