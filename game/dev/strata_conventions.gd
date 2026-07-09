class_name StrataConventions
## Naming shared by the game's Strata seam (strata_link.gd, the live
## in-engine preview/reload) and the offline importer
## (tools/strata/import_world.gd, the P0 byte-identical bake copy). Both
## read/write the SAME blessed tile + region record; "baked_world" is a
## Strata convention — the reserved id for the one live world tile — not
## valley content (PLAN_FRAMEWORK Q1). Named once here so neither file
## hand-types it and the two copies can't drift.

const BAKED_WORLD_ID := "baked_world"
const BAKED_TILE_PATH := "res://data/terrain/tiles/" + BAKED_WORLD_ID + ".exr"
const BAKED_REGION_PATH := "res://data/regions/" + BAKED_WORLD_ID + ".json"
