extends Node3D
## Builds the water surface meshes for every record in data/water/ — the
## scene no longer hardcodes water geometry. Lakes become vertex-dense
## discs, rivers dense ribbons, because tier 2.5 (the wave field)
## displaces water VERTICES — a flat quad can't ripple. Surfaces track
## Hydrology levels; river flow speed follows real discharge.

const WATER_SHADER := preload("res://game/shaders/water.gdshader")
const DISC_STEP := 0.9  # meters between lake verts (ripple-scale)
const RIBBON_STEP := 1.8  # meters between river cross-sections
const RIBBON_ACROSS := 5
const EDGE_TUCK := 0.4  # ribbon reaches past the waterline into the bank
const STEP_SPLIT := 1.1  # a POOL LIP (flat above, cliff below) this tall
	# gets a vertical fall face; sustained steep runs stay continuous —
	# splitting every steep row turned cascades into shingles.
const STEP_FLAT := 0.35  # "flat above" threshold for lip detection
const FALL_FOAM_R := 10.0  # ribbon foams full within this of a waterfall lip
# W2 on lakes (ONE_APP P2): a lake with real fetch rides a scaled share
# of the swell and carries baked bathymetry, so storm chop shoals and
# dies at its shore exactly like the sea's. Ponds stay glassy.
const LAKE_SWELL_MIN_R := 40.0

var _lake_meshes: Dictionary = {}
var _river_meshes: Dictionary = {}
var _river_mats: Dictionary = {}
var _river_built_level: Dictionary = {}  # level each ribbon was built at

# The world sea (Terrain.sea_level): three meshes. A wave-capable patch
# rides with the focus (the 512² wave window is what displaces verts —
# density past it is wasted), a mid disc dense enough to carry the
# Gerstner swell (W1) out to where it stops reading, and a coarse static
# disc carries the surface to the horizon. Each tier sits a step lower
# to avoid z-fighting where they overlap; the shader fades the swell to
# flat at the mid rim so the far disc takes over seamlessly.
# W2 shoaling: the near patch + mid disc also carry BAKED BATHYMETRY —
# CUSTOM0 = (depth below sea level, ∇depth) per vertex, sampled from the
# real seabed via the kernel's height_block on a worker thread. The
# shader shoals and breaks the swell against it, so the breaker line
# follows reefs and bars. A tier's snap-move WAITS for its bake: mesh
# position and depth data land in the same frame (a stale bake would
# slide the surf line off the seabed). Without the native kernel the
# depth stays at its deep default — pure W1 swell, no shoaling.
const SEA_NEAR_RADIUS := 300.0
const SEA_NEAR_STEP := 3.0
const SEA_MID_RADIUS := 1600.0
const SEA_MID_STEP := 12.0  # carries the 37-60m storm swell bands
const SEA_FAR_RADIUS := 9000.0
const SEA_FAR_STEP := 250.0
const BATHY_DEEP := 1000.0  # "no data" depth: shoaling math degenerates to W1
const BATHY_FMT: int = Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
var _sea_near: MeshInstance3D
var _set_sea_level := -1e9  # last-applied tide (perf guard)
var _sea_mid: MeshInstance3D
var _sea_far: MeshInstance3D
var _bathy: Dictionary = {}  # tier -> bake state (see _bathy_register)


func _ready() -> void:
	add_to_group(PreviewTerrain.STEPS_ASIDE_GROUP)  # sea + lakes step aside during preview
	if Terrain.sea_level > -1e11:
		_sea_near = MeshInstance3D.new()
		_sea_near.name = "sea_near"
		_sea_near.mesh = _disc(SEA_NEAR_RADIUS, SEA_NEAR_STEP)
		_sea_near.mesh.surface_set_material(0, _sea_material(SEA_NEAR_STEP, 0.0))
		_sea_near.extra_cull_margin = 4.0
		_sea_near.position.y = Terrain.sea_level
		add_child(_sea_near)
		_sea_mid = MeshInstance3D.new()
		_sea_mid.name = "sea_mid"
		_sea_mid.mesh = _disc(SEA_MID_RADIUS, SEA_MID_STEP)
		_sea_mid.mesh.surface_set_material(0,
				_sea_material(SEA_MID_STEP, SEA_MID_RADIUS))
		_sea_mid.extra_cull_margin = 4.0
		_sea_mid.position.y = Terrain.sea_level - 0.07
		add_child(_sea_mid)
		_sea_far = MeshInstance3D.new()
		_sea_far.name = "sea_far"
		_sea_far.mesh = _disc(SEA_FAR_RADIUS, SEA_FAR_STEP)
		_sea_far.mesh.surface_set_material(0, _material(Vector2.ZERO))
		_sea_far.position.y = Terrain.sea_level - 0.15
		add_child(_sea_far)
		# W2: the shoaling tiers get their bathymetry channel.
		_bathy_register("near", _sea_near, SEA_NEAR_RADIUS, SEA_NEAR_STEP,
				Terrain.sea_level)
		_bathy_register("mid", _sea_mid, SEA_MID_RADIUS, SEA_MID_STEP,
				Terrain.sea_level)
	for w in Terrain.water_bodies:
		var center: Vector2 = w.center
		var mi := MeshInstance3D.new()
		mi.name = String(w.id)
		# Big imported lakes coarsen their grid so vert counts stay sane —
		# a 2km "lake" is an inland sea and carries swell like the sea's
		# mid disc, not pond ripples (the wave window's ±12cm would be
		# invisible on its step anyway).
		var radius := float(w.radius)
		var lake_step := maxf(DISC_STEP, radius / 128.0)
		# The imported shoreline (P2+) rides in world XZ; build the surface
		# grid clipped to the REAL polygon (centered on `center`, like the
		# disc). No outline (authored/pre-outline lake) ⇒ the equal-area disc.
		var outline: PackedVector2Array = w.get("outline", PackedVector2Array())
		if outline.size() >= 3:
			mi.mesh = _polygon_disc(_local_outline(outline, center), lake_step)
		else:
			mi.mesh = _disc(radius, lake_step)
		var lake_mat := _material(Vector2.ZERO)
		if radius >= LAKE_SWELL_MIN_R:
			# Fetch-scaled swell + real bathymetry (CUSTOM0): the shader's
			# W2 path shoals, steepens, and breaks the chop on the lake's
			# own shallows — and the surf criterion kills it at the shore.
			lake_mat.set_shader_parameter("swell_boost",
					clampf(radius / 600.0, 0.1, 0.5))
			lake_mat.set_shader_parameter("swell_step", lake_step)
			lake_mat.set_shader_parameter("swell_fade_radius", radius)
			lake_mat.set_shader_parameter("bathy_boost", 1.0)
		mi.mesh.surface_set_material(0, lake_mat)
		mi.extra_cull_margin = 2.0  # waves leave the flat AABB
		mi.position = Vector3(center.x,
				float(w.surface) + Terrain.lake_levels[w.idx], center.y)
		add_child(mi)
		_lake_meshes[w.id] = mi
		if radius >= LAKE_SWELL_MIN_R:
			_bathy_register("lake:" + String(w.id), mi, radius, lake_step,
					float(w.surface))
	for r in Terrain.rivers:
		_build_river_mesh(r)
	Hydrology.levels_changed.connect(_on_levels_changed)
	# The map river pen adds rivers at runtime; give each its ribbon.
	Terrain.river_added.connect(_build_river_mesh)
	# A whole-water reload (reload_world / import) swaps the river set out from
	# under us — rebuild every ribbon so imported rivers render (and drop the
	# meshes of any that the reload removed). Hydrology re-seeds first (it
	# connects earlier, as an autoload), so the fresh ribbons read live flow.
	Terrain.water_reloaded.connect(_rebuild_rivers)
	# Mission Y3: the sea/lake bathymetry (_bathy) is a FOLLOW cache keyed
	# on the focus-snapped anchor — _bathy_follow only rebakes when that
	# anchor moves, never on its own. A lake's anchor never moves (its
	# disc is fixed at the lake center — a genuine one-shot bake by
	# design), and the sea's near/mid tiers only rebake once the player
	# happens to wander to a new snap cell. Neither listens for the
	# ground changing under them, so a bless (reload_world's whole-frame
	# edited, or a sculpted stroke) leaves stale seabed depth live under
	# the water indefinitely — the shoaling/surf line keeps breaking on
	# the OLD reef. Forcing the anchor back to INF here just makes
	# _bathy_follow treat the (unchanged) goal as new next tick, so it
	# re-bakes off the CURRENT terrain — same one-shot-per-anchor design,
	# just no longer blind to the ground moving under a fixed anchor.
	Terrain.edited.connect(_on_terrain_edited_bathy)


## Rebuild all river ribbons after a whole-water reload: free the meshes of
## rivers that no longer exist, then (re)build every current one. Keyed by id,
## so a river that survived the reload keeps its node but gets fresh geometry.
func _rebuild_rivers() -> void:
	var live := {}
	for r in Terrain.rivers:
		live[r.id] = true
	for id in _river_meshes.keys():
		if not live.has(id):
			_river_meshes[id].queue_free()
			_river_meshes.erase(id)
			_river_mats.erase(id)
			_river_built_level.erase(id)
	for r in Terrain.rivers:
		_build_river_mesh(r)


## Build (or rebuild) one river's ribbon mesh + flow material — shared by
## the boot loop and the runtime pen (Terrain.river_added).
func _build_river_mesh(r: Dictionary) -> void:
	var mi: MeshInstance3D = _river_meshes.get(r.id)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = String(r.id)
		mi.extra_cull_margin = 2.0
		add_child(mi)
		_river_meshes[r.id] = mi
	# Rivers flow by their per-vertex map (UV2), not the whole-mesh drift:
	# direction lives in the mesh, speed in flow_scale.
	var mat := _material(Vector2.ZERO)
	mat.set_shader_parameter("rapids_boost", 1.0)
	mat.set_shader_parameter("flow_scale", _flow_speed(r.id))
	# Mouth feather (S2): ribbons draw AFTER lake discs so the feathered
	# alpha blends over the lake instead of racing it in the sort.
	mat.render_priority = 1
	mi.mesh = _ribbon(r.nodes, Terrain.river_levels[r.idx], float(r.depth),
			r.get("falls", []), _mouth_for(r.nodes))
	_river_built_level[r.id] = Terrain.river_levels[r.idx]
	mi.mesh.surface_set_material(0, mat)
	_river_mats[r.id] = mat


func _process(_delta: float) -> void:
	# The map keeps the real water in view (2026-07-08, the orbit map):
	# sea, lakes, and rivers ARE chart information — the surfaces follow
	# the map focus below, and the chart palette that used to stand in
	# for them is retired with the flat map.
	# Fill-channels experiment (debug K): the sim fills the carved beds,
	# so hide the sculpted ribbons — the two shouldn't stack.
	var hide_rivers: bool = WaterField.enabled and WaterField.fill_channels
	for id in _river_meshes:
		var mi: MeshInstance3D = _river_meshes[id]
		if mi.visible == hide_rivers:
			mi.visible = not hide_rivers
	# Lake bathymetry is a ONE-SHOT bake (the disc never moves): the
	# follow kicks it, polls the worker, and no-ops once it has landed.
	for tier in _bathy:
		if String(tier).begins_with("lake:"):
			var mi: MeshInstance3D = _bathy[tier].mi
			_bathy_follow(tier, Vector2(mi.position.x, mi.position.z))
	if _sea_near == null:
		return
	var focus := Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player")
	# An open map drives the view even in the Toolkit (same rule as the
	# streamer): the sea reaches wherever the map is looking.
	if MapScreen.active:
		var p := MapScreen.focus_position()
		focus = Vector2(p.x, p.z)
	elif Toolkit.active:
		var p := Toolkit.cam_position()
		focus = Vector2(p.x, p.z)
	elif player:
		focus = Vector2(player.global_position.x, player.global_position.z)
	# Snapped so the wave-sampling verts don't shimmer as the focus moves.
	# W2: the shoaling tiers move through _bathy_follow, which rebakes
	# their seabed depth for each new anchor before the mesh jumps.
	_bathy_follow("near", focus.snappedf(SEA_NEAR_STEP * 2.0))
	_bathy_follow("mid", focus.snappedf(SEA_MID_STEP * 2.0))
	# The far disc follows too (coarse snap): static at the origin it
	# ran out 6km short of the horizon on far coasts — a visible band of
	# missing sea from any strand past ~3km out.
	var far_focus := focus.snappedf(SEA_FAR_STEP * 2.0)
	if _sea_far.position.x != far_focus.x or _sea_far.position.z != far_focus.y:
		_sea_far.position.x = far_focus.x
		_sea_far.position.z = far_focus.y
	# The orbit map sees to the world's rim and past it: stretch the far
	# disc so beyond-the-tile reads as OCEAN, not the far-LOD's bare
	# seabed squares (the flat map's palette used to paper over those;
	# the real 3D map needs the real sea to do it). Distant + flat, so
	# the coarse verts stretch invisibly; back to 1x when the map closes.
	var reach := 5.0 if MapScreen.active else 1.0
	if _sea_far.scale.x != reach:
		_sea_far.scale = Vector3(reach, 1.0, reach)
		# The map's narrowed FOV (map_screen.gd MAP_FOV) keeps the visible
		# ground/sea well inside this disc's radius at the map's own steep
		# chart angles, but a shallow drag can still put the disc's own
		# hard circular edge in frame — the planet-limb bug. Fade ALPHA
		# toward the true edge on the map camera only; rim_fade_radius is
		# in the mesh's OBJECT space (pre-scale), so it stays SEA_FAR_RADIUS
		# regardless of the 5x stretch above.
		var far_mat := _sea_far.mesh.surface_get_material(0) as ShaderMaterial
		far_mat.set_shader_parameter(
			"rim_fade_radius", SEA_FAR_RADIUS if MapScreen.active else 0.0)
	# The tide: all sheets ride the live surface, and the strand
	# shader's dark band follows it via the sea_level global.
	var live: float = Terrain.sea_surface()
	# Move the sheets and push the global only when the tide has moved a
	# tenth of a millimeter (perf 2026-07-09): between tide steps these
	# were redundant transform dirties + RenderingServer traffic at
	# frame rate. The live value stays exact for every reader.
	if absf(live - _set_sea_level) > 1e-4:
		_set_sea_level = live
		_sea_near.position.y = live
		_sea_mid.position.y = live - 0.07
		_sea_far.position.y = live - 0.15
		RenderingServer.global_shader_parameter_set("sea_level", live)


func _on_levels_changed() -> void:
	for w in Terrain.water_bodies:
		var mi: MeshInstance3D = _lake_meshes.get(w.id)
		if mi:
			mi.position.y = float(w.surface) + Terrain.lake_levels[w.idx]
	# The live level is a constant offset over the whole ribbon —
	# TRANSLATE the built mesh instead of rebuilding it. (The hourly
	# rebuild was 80ms across all rivers once the drape sampled
	# Terrain.height per row — it was the dev time-skip lag.)
	for r in Terrain.rivers:
		var mi: MeshInstance3D = _river_meshes.get(r.id)
		if mi:
			mi.position.y = Terrain.river_levels[r.idx] \
				- float(_river_built_level[r.id])
			_river_mats[r.id].set_shader_parameter("flow_scale",
					_flow_speed(r.id))


## Stripe drift speed from real discharge: baseline ~1, floods ~2.
func _flow_speed(river_id: String) -> float:
	return 2.0 * Hydrology.flow_norm(river_id)


## Mouth feather (S2, the flagged river-into-lake seam): if a river's
## last node lands on a lake disc, the ribbon feathers into it — alpha
## ramp + flow fade + surface dropped to the lake's LIVE level over the
## last ~two widths, so the hyd rivers stop ending in drawn lines.
## Returns {} for rivers that end anywhere else (the sea has W2 surf;
## a dry wash just ends).
func _mouth_for(nodes: Array) -> Dictionary:
	if nodes.size() < 2 or OS.get_environment("WATER_NO_MOUTH") == "1":
		return {}  # env gate: the probe's before/after A/B only
	var last: Dictionary = nodes[nodes.size() - 1]
	var lp: Vector2 = last.pos
	for w in Terrain.water_bodies:
		if lp.distance_to(w.center) < float(w.radius) + float(last.half) * 2.0:
			return {"level": float(w.surface) + Terrain.lake_levels[w.idx],
				"span": clampf(4.0 * float(last.half), 6.0, 30.0)}
	return {}


func _material(flow: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("flow", flow)
	return mat


## Sea-tier material: the Gerstner swell (W1) displaces these meshes.
## step tells the shader which swell bands the grid can carry (shorter
## ones fade instead of aliasing); fade_radius > 0 eases the swell flat
## at the mesh rim so the coarse far disc takes over without a seam.
func _sea_material(step: float, fade_radius: float) -> ShaderMaterial:
	var mat := _material(Vector2.ZERO)
	mat.set_shader_parameter("swell_boost", 1.0)
	mat.set_shader_parameter("swell_step", step)
	mat.set_shader_parameter("swell_fade_radius", fade_radius)
	mat.set_shader_parameter("bathy_boost", 1.0)  # W2: CUSTOM0 carries the seabed
	return mat


## W2: give one water surface its bathymetry channel — rebuild the disc's
## surface with a CUSTOM0 slot (depth + ∇depth per vertex, RGB float),
## deep-defaulted so the swell stays pure W1 until the first bake lands.
## `level` is the surface the depth is measured from: sea level for the
## sea tiers, the authored surface for a lake (ONE_APP P2 — imported
## lakes shoal their own chop).
func _bathy_register(tier: String, mi: MeshInstance3D, radius: float, step: float,
		level: float) -> void:
	var mesh: ArrayMesh = mi.mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var mat: Material = mesh.surface_get_material(0)
	var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var n := int(ceil(radius * 2.0 / step)) + 2
	if vcount != n * n:
		push_warning("[water] sea %s: %d verts != %d² grid — no bathymetry" % [
			tier, vcount, n])
		return
	var custom := PackedFloat32Array()
	custom.resize(vcount * 3)
	for i in vcount:
		custom[i * 3] = BATHY_DEEP
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, BATHY_FMT)
	mesh.surface_set_material(0, mat)
	_bathy[tier] = {"mi": mi, "radius": radius, "step": step, "n": n,
		"level": level, "arrays": arrays, "anchor": Vector2.INF,
		"goal": Vector2.INF, "task": -1, "out": PackedFloat32Array()}


## Mission Y3: a world edit (sculpt commit, or a whole-frame reload_world
## bless) invalidates any registered tier whose bake footprint the edit
## touches — its NEXT _bathy_follow call (every _process, regardless of
## whether the focus/anchor moved) rebakes off the live seabed instead of
## trusting the depth data it baked before the edit. Untouched tiers (an
## edit on the far side of the world from a lake) are left alone — same
## economy as far_terrain's own rect-scoped _invalidate.
func _on_terrain_edited_bathy(world_rect: Rect2) -> void:
	for tier: String in _bathy:
		var st: Dictionary = _bathy[tier]
		var anchor: Vector2 = st.anchor
		if not anchor.is_finite():
			continue  # never baked yet — its first bake reads live ground anyway
		var r: float = st.radius
		var footprint := Rect2(anchor.x - r, anchor.y - r, r * 2.0, r * 2.0)
		if footprint.intersects(world_rect):
			st.anchor = Vector2.INF


## W2: move one sea tier to `goal`, rebaking its seabed for the new
## anchor first (kernel, worker thread) so the depth attribute and the
## mesh position swap in the same frame — the surf line never slides off
## the seabed. Without the native kernel the tiers still follow the
## focus but keep their deep default (bulk seabed sampling in GDScript
## would hitch on-main and crash off-main; see Terrain.height_block).
func _bathy_follow(tier: String, goal: Vector2) -> void:
	var st: Dictionary = _bathy.get(tier, {})
	if st.is_empty() or Terrain.kernel == null \
			or DisplayServer.get_name() == "headless":
		# Unregistered/kernel-less tiers still follow (deep default = W1).
		var direct: MeshInstance3D = st.get("mi",
				_sea_near if tier == "near" else _sea_mid)
		if direct:
			direct.position.x = goal.x
			direct.position.z = goal.y
		return
	var task: int = st.task
	if task >= 0:
		if not WorkerThreadPool.is_task_completed(task):
			return  # the tier trails one snap until its bake lands
		WorkerThreadPool.wait_for_task_completion(task)
		st.task = -1
		_bathy_apply(st)
	if Vector2(st.anchor) != goal:
		st.goal = goal
		st.task = WorkerThreadPool.add_task(_bathy_bake.bind(st, goal),
			false, "sea bathymetry " + tier)


## Worker thread (W2): sample the real seabed on the disc's own vertex
## grid — one kernel height_block, never per-sample GDScript off-main
## (the descent-crash law) — and write depth + central-difference ∇depth.
func _bathy_bake(st: Dictionary, anchor: Vector2) -> void:
	var n: int = st.n
	var step: float = st.step
	var radius: float = st.radius
	var h := Terrain.height_block(anchor.x - radius, anchor.y - radius, step, n, n)
	var level: float = st.level
	var custom := PackedFloat32Array()
	custom.resize(n * n * 3)
	var inv2 := 1.0 / (2.0 * step)
	for iz in n:
		var row := iz * n
		var zm := maxi(iz - 1, 0) * n
		var zp := mini(iz + 1, n - 1) * n
		for ix in n:
			var i := row + ix
			custom[i * 3] = level - h[i]
			# ∇depth = -∇height (rim rows fall back to one-sided).
			custom[i * 3 + 1] = -(h[row + mini(ix + 1, n - 1)]
					- h[row + maxi(ix - 1, 0)]) * inv2
			custom[i * 3 + 2] = -(h[zp + ix] - h[zm + ix]) * inv2
	st.out = custom


## Main thread (W2): a finished bake swaps in — fresh CUSTOM0, mesh moved
## to the anchor it was baked for, atomically.
func _bathy_apply(st: Dictionary) -> void:
	var arrays: Array = st.arrays
	arrays[Mesh.ARRAY_CUSTOM0] = st.out
	var mi: MeshInstance3D = st.mi
	var mesh: ArrayMesh = mi.mesh
	var mat: Material = mesh.surface_get_material(0)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, BATHY_FMT)
	mesh.surface_set_material(0, mat)
	var goal: Vector2 = st.goal
	mi.position.x = goal.x
	mi.position.z = goal.y
	if not Vector2(st.anchor).is_finite():
		# First bake: say what the seabed under this tier looks like once
		# (the probe + Toolkit read this to trust the surf line).
		var out: PackedFloat32Array = st.out
		var dmin := 1e12
		var dmax := -1e12
		for i in range(0, out.size(), 3):
			dmin = minf(dmin, out[i])
			dmax = maxf(dmax, out[i])
		print("[water] bathymetry %s live: depth %.1f..%.1fm at (%.0f, %.0f)" % [
			mi.name, dmin, dmax, goal.x, goal.y])
	st.anchor = goal


func _exit_tree() -> void:
	# WorkerThreadPool ids must be waited on before the pool tears down.
	for tier in _bathy:
		var st: Dictionary = _bathy[tier]
		if int(st.task) >= 0:
			WorkerThreadPool.wait_for_task_completion(int(st.task))


# A vertex-dense disc: every corner of a DISC_STEP grid (clamped to the
# rim), triangulated wherever a cell touches the circle. Plain loops —
# no lambda captures (a captured int counter froze and degenerated every
# triangle to vertex 0: mesh present, nothing drawn. The invisible-pond
# bug of 2026-07-04.)
func _disc(radius: float, step: float = DISC_STEP) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(radius * 2.0 / step)) + 2
	for iz in n:
		for ix in n:
			var p := Vector2(ix * step - radius, iz * step - radius)
			if p.length() > radius:
				p = p.normalized() * radius
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	for iz in n - 1:
		for ix in n - 1:
			var inside := 0
			for c in [[ix, iz], [ix + 1, iz], [ix, iz + 1], [ix + 1, iz + 1]]:
				var p := Vector2(c[0] * step - radius, c[1] * step - radius)
				if p.length() <= radius:
					inside += 1
			if inside == 0:
				continue
			var a := iz * n + ix
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	return st.commit()


# The ground-hugging water surface for a resampled ribbon (pure geometry,
# so it is unit-testable with a synthetic terrain sampler). `row_pos` are
# the per-row world XZ points, `row_surf` the node-lerped record waterline
# at each, `height_fn(x, z) -> float` samples the terrain. Returns the
# per-row water surface (record level, relative to the whole-ribbon base).
#
# Two constraints, reconciled: the surface must not run visibly uphill
# (pool flat behind lips) AND must not float above the ground between the
# coarse record nodes. Draping under `terrain + depth` gives the second;
# a downstream max-scan gives the first — but the max-scan is CLAMPED back
# under the local drape ceiling so a pool never rises above the ground
# that would contain it. Contained channels still pool; open dips and
# meander shortcuts step down and hug the floor.
static func _drape(row_pos: Array, row_surf: PackedFloat32Array,
		depth: float, height_fn: Callable) -> PackedFloat32Array:
	var n := row_pos.size()
	var ceil_surf := PackedFloat32Array(); ceil_surf.resize(n)
	var surf := PackedFloat32Array(); surf.resize(n)
	for i in n:
		var p: Vector2 = row_pos[i]
		ceil_surf[i] = float(height_fn.call(p.x, p.y)) + depth
		surf[i] = minf(row_surf[i], ceil_surf[i])
	for i in range(n - 2, -1, -1):
		surf[i] = minf(maxf(surf[i], surf[i + 1]), ceil_surf[i])
	return surf


# The imported world-space shoreline shifted into a lake's LOCAL frame
# (relative to its center), so the outline mesh sits under the same
# mi.position — and therefore the same lake_levels offset path — as the disc.
func _local_outline(outline: PackedVector2Array, center: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(outline.size())
	for i in outline.size():
		out[i] = outline[i] - center
	return out


# A vertex-dense surface clipped to the lake's REAL outline — the disc's
# grid generalized from a circle to an arbitrary polygon. Every DISC_STEP
# grid corner inside the polygon stays put; every outside corner snaps to
# the nearest point on the shoreline; a cell emits its two triangles
# whenever at least one corner is inside. So the surface reaches EXACTLY to
# the true shore (no floating rim where a disc overhung the pool, no dry
# gap) while keeping the vertex density the wave field displaces. Plain
# loops, no lambda captures (the invisible-pond bug of 2026-07-04).
func _polygon_disc(poly: PackedVector2Array, step: float = DISC_STEP) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lo -= Vector2(step, step)  # a cell of margin so the boundary ring builds
	hi += Vector2(step, step)
	var nx := int(ceil((hi.x - lo.x) / step)) + 1
	var nz := int(ceil((hi.y - lo.y) / step)) + 1
	var inside := PackedByteArray()
	inside.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var p := Vector2(lo.x + ix * step, lo.y + iz * step)
			var isin := _point_in_poly(p, poly)
			inside[iz * nx + ix] = 1 if isin else 0
			if not isin:
				p = _nearest_on_poly(p, poly)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			if inside[a] == 0 and inside[a + 1] == 0 \
					and inside[a + nx] == 0 and inside[a + nx + 1] == 0:
				continue
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
			st.add_index(a + nx)
	return st.commit()


# Even-odd ray cast: is p inside the closed polygon?
func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y):
			var t := (p.y - a.y) / (b.y - a.y)
			if p.x < a.x + t * (b.x - a.x):
				inside = not inside
		j = i
	return inside


# The closest point on the polygon boundary to p (min over all edges) — an
# outside grid corner snaps here so the mesh meets the shore exactly.
func _nearest_on_poly(p: Vector2, poly: PackedVector2Array) -> Vector2:
	var best := poly[0]
	var bestd := INF
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[j]
		var b := poly[i]
		var ab := b - a
		var t := 0.0
		var len2 := ab.length_squared()
		if len2 > 1e-9:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < bestd:
			bestd = d
			best = q
		j = i
	return best


# A dense ribbon: the spline resampled every RIBBON_STEP meters with
# RIBBON_ACROSS verts per cross-section. World-space (seam-free with the
# pond under the shared world-reading shader).
# The DRAPE (2026-07-05, ground-clamped 2026-07-09): record nodes carry
# one surface each and the terrain undulates between them, so a node-lerped
# surface either floats over dips or bridges spurs. Every row takes
# min(node-lerped surface, carved centerline ground + depth) — identical
# to the record waterline on normal spans (the carve puts the bed exactly
# depth below it), but following the terrain down through dips — then the
# downstream pooling max-scan (see _drape) makes the surface monotone
# WHERE the ground contains it, clamped to the drape ceiling so it never
# lifts a row into the air over the coarse-node dips (the float bug).
# Steep row-to-row drops are written into COLOR.r → shader rapids foam.
# `mouth` (S2): {level: lake's live surface (absolute), span: meters} —
# the last span of the ribbon feathers into its lake: COLOR.a ramps 1→0
# (the shader honors it as ALPHA), UV2 flow fades to zero so advection
# agrees, and the surface eases down to the lake level so the geometry
# meets the disc instead of shelving over it.
func _ribbon(nodes: Array, level: float, depth: float,
		falls: Array = [], mouth: Dictionary = {}) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Resample the polyline.
	var rows: Array = []
	var carry := 0.0
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i]
		var b: Dictionary = nodes[i + 1]
		var pa: Vector2 = a.pos
		var ab: Vector2 = b.pos - pa
		var seg_len := ab.length()
		if seg_len < 1e-4:
			continue
		var s := carry
		while s < seg_len:
			var f := s / seg_len
			rows.append([pa + ab * f, lerpf(a.half, b.half, f),
				lerpf(a.surface, b.surface, f), ab.normalized()])
			s += RIBBON_STEP
		carry = s - seg_len
	var last: Dictionary = nodes[nodes.size() - 1]
	var prev: Dictionary = nodes[nodes.size() - 2]
	rows.append([last.pos, float(last.half), float(last.surface),
		(Vector2(last.pos) - Vector2(prev.pos)).normalized()])
	# Drape, then pool WITHIN the ground. The old max-scan lifted every row
	# to the highest waterline downstream of it (pooling flat behind lips) —
	# but the polyline's nodes are ~48m apart, and between them the terrain
	# dips and meanders below the straight record line. An unbounded lift
	# bridged those dips into the air: the ribbon floated meters above the
	# valley floor (the reported bug). The lift is now CLAMPED to the drape
	# ceiling (terrain + depth) at each row, so a pool can rise only as high
	# as its own banks — where terrain contains it (a cut channel) the water
	# still pools flat behind a lip, and where it does not (an open dip or a
	# meander shortcut) the surface steps DOWN into the dip and hugs the
	# floor instead of hanging over it. The drape samples terrain per row
	# (RIBBON_STEP ~1.8m), so min() follows the ground at fine resolution.
	var row_pos: Array = []
	var row_surf := PackedFloat32Array(); row_surf.resize(rows.size())
	for i in rows.size():
		row_pos.append(rows[i][0])
		row_surf[i] = rows[i][2]
	var surf := _drape(row_pos, row_surf, depth, Terrain.height)
	# Seam fixes (2026-07-05, the Skyrim lessons — bed and surface must
	# AGREE, and where they can't, hide the disagreement):
	#  - tangents smoothed over ±2 rows so cross-sections stop crossing
	#    on tight bends (the notch);
	#  - edges tucked EDGE_TUCK past the waterline so they bury in the
	#    carved bank instead of meeting the terrain edge-on (the crack);
	#  - big drops become a lip row + a vertical fall face instead of
	#    one stretched quad the terrain pokes through (the sliver).
	var tans: Array = []
	for i in rows.size():
		var t: Vector2 = Vector2.ZERO
		for j in range(maxi(i - 2, 0), mini(i + 3, rows.size())):
			t += rows[j][3]
		tans.append(t.normalized() if t.length() > 1e-4 else rows[i][3])
	var final_rows: Array = []  # [pos, half, surface, tangent]
	for i in rows.size():
		final_rows.append([rows[i][0], rows[i][1] + EDGE_TUCK, surf[i], tans[i]])
		if i > 0 and i < rows.size() - 1 \
				and surf[i] - surf[i + 1] > STEP_SPLIT \
				and surf[i - 1] - surf[i] < STEP_FLAT:
			# A pool lip: flat water arriving at a cliff. Carry the
			# upstream surface to the downstream spot so the next row
			# drops straight down (a fall face) instead of one long
			# stretched quad the terrain pokes through.
			final_rows.append([rows[i + 1][0], rows[i + 1][1] + EDGE_TUCK,
				surf[i], tans[i + 1]])
	# Rapids strength from the local grade (COLOR.r → shader foam). A
	# Strata waterfall (knickpoint record, ONE_APP P2) foams FULL around
	# its lip — the carve already made the drop; the record guarantees
	# the white water, whatever the drape's local row grade says.
	var rapids := PackedFloat32Array(); rapids.resize(final_rows.size())
	for i in final_rows.size():
		var drop := 0.0
		if i < final_rows.size() - 1:
			drop = float(final_rows[i][2]) - float(final_rows[i + 1][2])
		rapids[i] = smoothstep(0.06, 0.30, drop / RIBBON_STEP)
		for fl in falls:
			if Vector2(final_rows[i][0]).distance_to(fl.pos) \
					< FALL_FOAM_R + float(fl.drop):
				rapids[i] = 1.0
				break
	# Mouth feather (S2): walk back from the end, ramping 0→1 over the
	# span. The surface eases to the lake's live level (kept monotone —
	# both lerp endpoints are) and the drawn line dissolves.
	var feather := PackedFloat32Array(); feather.resize(final_rows.size())
	feather.fill(1.0)
	if not mouth.is_empty():
		var span: float = mouth.span
		var lake_local: float = float(mouth.level) - level
		var dist := 0.0
		for i in range(final_rows.size() - 1, -1, -1):
			if i < final_rows.size() - 1:
				dist += Vector2(final_rows[i][0]) \
						.distance_to(Vector2(final_rows[i + 1][0]))
			if dist >= span:
				break
			var tt := clampf(dist / span, 0.0, 1.0)
			feather[i] = tt
			final_rows[i][2] = lerpf(lake_local, float(final_rows[i][2]), tt)
	# Emit rows of verts, stitch quads. UV2 is the FLOW MAP: downstream
	# direction × a local pace (rapids race, pools laze) — the shader
	# advects ripples and foam along it, scaled by the live discharge.
	# COLOR carries rapids in .r and the mouth feather in .a.
	for i in final_rows.size():
		var row: Array = final_rows[i]
		var perp: Vector2 = Vector2(-row[3].y, row[3].x)
		# Rapids die with the feather too: the eased-to-lake drop must not
		# read as white water while the ribbon dissolves.
		st.set_color(Color(rapids[i] * feather[i], 0.0, 0.0, feather[i]))
		var tan_v: Vector2 = row[3]
		st.set_uv2(tan_v * (0.7 + 1.8 * rapids[i]) * feather[i])
		for k in RIBBON_ACROSS:
			var u := (float(k) / (RIBBON_ACROSS - 1)) * 2.0 - 1.0
			var p: Vector2 = row[0] + perp * (u * row[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, float(row[2]) + level, p.y))
	for i in final_rows.size() - 1:
		for k in RIBBON_ACROSS - 1:
			var a := i * RIBBON_ACROSS + k
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + RIBBON_ACROSS)
			st.add_index(a + 1)
			st.add_index(a + RIBBON_ACROSS + 1)
			st.add_index(a + RIBBON_ACROSS)
	return st.commit()
