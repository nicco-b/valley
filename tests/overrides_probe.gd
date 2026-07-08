extends Node
## Overrides round-trip probe (dev-only, P4): the headless proof that
## hand work survives a geology re-roll. Two modes via OV_MODE:
##
##   dress — place two records + paint a +12m pen knoll at PEN, save the
##           layers, emit overrides.json; prints the ids and the
##           effective ground at PEN. Run BEFORE re-rolling in Strata.
##   check — after a new world imported: prints the RAW tile height at
##           PEN (the pure bake), the effective ground (raw + hand
##           layers), each record's seat vs the current ground (the
##           ground_dy law: seat - ground == dy, nothing floats or
##           buries), and the `overrides status` line.
##
##   OV_MODE=dress godot --headless --quit-after 300 res://tests/overrides_probe.tscn
##
## Autoloads only — no world scene, no player; leaves the checkout
## dressed on purpose (this probe IS the dressing hand).

const PEN := Vector2(1024.0, -512.0)
const SPOT_A := Vector2(60.0, -300.0)    # valley floor
const SPOT_B := Vector2(1500.0, -1500.0)  # mid-slope


func _ready() -> void:
	match OS.get_environment("OV_MODE"):
		"dress":
			_dress()
		"check":
			_check()
		_:
			print("OV_MODE=dress|check required")
	get_tree().quit()


func _dress() -> void:
	var ga := Terrain.height(SPOT_A.x, SPOT_A.y)
	var gb := Terrain.height(SPOT_B.x, SPOT_B.y)
	var r1: Dictionary = CellRecords.add(
		Vector3(SPOT_A.x, ga + 0.4, SPOT_A.y), "boulder_a", 0.7, 1.0)
	var r2: Dictionary = CellRecords.add(
		Vector3(SPOT_B.x, gb, SPOT_B.y), "pine_b", 1.9, 1.3)
	var before := Terrain.height(PEN.x, PEN.y)
	Terrain.commit_tile_override(Terrain.paint_tile_override(PEN, 180.0, 12.0))
	Terrain.save_tile_override()
	var counts: Dictionary = Overrides.emit()
	print("DRESS ids=%s,%s" % [r1["id"], r2["id"]])
	print("DRESS pen=(%.0f, %.0f) ground %.2f -> %.2f (hand +%.2fm)" % [
		PEN.x, PEN.y, before, Terrain.height(PEN.x, PEN.y),
		Terrain.height(PEN.x, PEN.y) - before])
	print("DRESS emitted placements=%d layers=%d" % [
		counts["placements"], counts["layers"]])


func _check() -> void:
	var raw := _raw_tile_height(PEN.x, PEN.y)
	var eff := Terrain.height(PEN.x, PEN.y)
	print("CHECK pen=(%.0f, %.0f) raw_tile=%.2f effective=%.2f hand_delta=%+.2fm" % [
		PEN.x, PEN.y, raw, eff, eff - raw])
	for cell: Vector2i in CellRecords.all_cells():
		for rec: Dictionary in CellRecords.records(cell):
			var g := Terrain.height(float(rec.x), float(rec.z))
			var seat: float = CellRecords.seat_y(rec)
			print("CHECK %s %s seat=%.2f ground=%.2f seat-ground=%+.2f (dy=%+.2f)" % [
				rec.get("id", "?"), rec.get("kit", "?"), seat, g, seat - g,
				float(rec.get("ground_dy", 0.0))])
	print("CHECK link: " + StrataLink._execute("overrides status"))


## The PURE bake under a point: bilinear straight off baked_world.exr,
## no pens, no sculpt — what Strata exported, nothing else.
func _raw_tile_height(x: float, z: float) -> float:
	var rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/regions/baked_world.json"))
	if not (rec is Dictionary):
		return NAN
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		String(rec["heightmap"])))
	if img == null:
		return NAN
	img.convert(Image.FORMAT_RF)
	var size := float(rec["size"])
	var x0 := float(rec["origin"]["x"])
	var z0 := float(rec["origin"]["z"])
	var res := img.get_width()
	var px := clampf((x - x0) / size * (res - 1), 0.0, res - 1.001)
	var pz := clampf((z - z0) / size * (res - 1), 0.0, res - 1.001)
	var ix := int(px)
	var iz := int(pz)
	var fx := px - ix
	var fz := pz - iz
	return lerpf(
		lerpf(img.get_pixel(ix, iz).r, img.get_pixel(ix + 1, iz).r, fx),
		lerpf(img.get_pixel(ix, iz + 1).r, img.get_pixel(ix + 1, iz + 1).r, fx),
		fz)
