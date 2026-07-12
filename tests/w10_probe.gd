extends Node
## Ad hoc W10 verification probe (not part of test.sh): boots the real
## valley and checks (1) the three water audio rows actually emit at a
## river reach / a fall's plunge base / the strand shoreline, and (2) the
## plunge-pool outward push in WaterField.current_at works.  Run:
##   godot --headless res://tests/w10_probe.tscn
var _world: Node
var _t := 0

func _ready() -> void:
	_world = load("res://game/world/valley.tscn").instantiate()
	add_child(_world)
	call_deferred("_probe")

func _probe() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var wa: Node = _world.get_node("WaterAudio")
	var river_emitters: Array = wa.get("_river_emitters")
	var falls_emitters: Array = wa.get("_falls_emitters")
	print("W10-AUDIO river_emitters=%d falls_emitters=%d rivers=%d" % [
		river_emitters.size(), falls_emitters.size(), Terrain.rivers.size()])
	for e in river_emitters:
		var river: Dictionary = Terrain.rivers[e.river_idx]
		print("  river_bed[%s] pos=%s volume_db=%.2f flow_norm=%.3f" % [
			String(river.id), e.player.position, e.player.volume_db,
			Hydrology.flow_norm(String(river.id))])
	for e in falls_emitters:
		var river: Dictionary = Terrain.rivers[e.river_idx]
		var fl: Dictionary = river.falls[e.fall_idx]
		print("  falls_roar[%s#%d] pos=%s volume_db=%.2f drop=%.1f flow_norm=%.3f" % [
			String(river.id), e.fall_idx, e.player.position, e.player.volume_db,
			float(fl.get("drop", 0.0)), Hydrology.flow_norm(String(river.id))])

	var amb: Node = _world.get_node("Ambience")
	var beds: Array = amb.get("_beds")
	for bed: Dictionary in beds:
		if String(bed.rec.get("id", "")) == "shore_lap":
			print("W10-AUDIO shore_lap bed loaded, biomes=%s day_gain=%.2f" % [
				bed.rec.get("biomes"), float(bed.rec.get("day_gain", 0.0))])

	# Plunge-pool wading check: find the first real fall (drop >= 1m) and
	# sample current_at just outside its base radius (should push OUTWARD).
	var found := false
	for r in Terrain.rivers:
		for fl in r.get("falls", []) as Array:
			var drop: float = float(fl.get("drop", 0.0))
			if drop < 1.0:
				continue
			var base: Vector2 = fl.get("base", fl.get("pos", Vector2.ZERO))
			var width: float = float(fl.get("width", 0.0))
			var radius := clampf(maxf(width * 0.5, 2.0) + drop * 0.15, 2.5, 11.0)
			# sample 1m inside the plunge radius, offset along +X from base
			var sample_xz := base + Vector2(radius * 0.6, 0.0)
			var y := Terrain.height(sample_xz.x, sample_xz.y)
			var cur := WaterField.current_at(Vector3(sample_xz.x, y, sample_xz.y))
			var outward := (sample_xz - base).normalized()
			var dotp := cur.normalized().dot(outward) if cur.length() > 0.001 else 0.0
			print("W10-PLUNGE river=%s drop=%.1f base=%s radius=%.2f sample=%s current=%s speed=%.2f outward_dot=%.3f" % [
				String(r.id), drop, base, radius, sample_xz, cur, cur.length(), dotp])
			found = true
			break
		if found:
			break
	if not found:
		print("W10-PLUNGE no fall with drop>=1m found in this world")

	get_tree().quit()
