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

var _lake_meshes: Dictionary = {}
var _river_meshes: Dictionary = {}
var _river_mats: Dictionary = {}
var _river_built_level: Dictionary = {}  # level each ribbon was built at

# The world sea (Terrain.sea_level): two meshes. A wave-capable patch
# rides with the focus (the 512² wave window is what displaces verts —
# density past it is wasted), and a coarse static disc carries the
# surface to the horizon. Far disc sits 15cm lower to avoid z-fighting
# where they overlap.
const SEA_NEAR_RADIUS := 300.0
const SEA_NEAR_STEP := 3.0
const SEA_FAR_RADIUS := 9000.0
const SEA_FAR_STEP := 250.0
var _sea_near: MeshInstance3D
var _sea_far: MeshInstance3D


func _ready() -> void:
	if Terrain.sea_level > -1e11:
		_sea_near = MeshInstance3D.new()
		_sea_near.name = "sea_near"
		_sea_near.mesh = _disc(SEA_NEAR_RADIUS, SEA_NEAR_STEP)
		_sea_near.mesh.surface_set_material(0, _material(Vector2.ZERO))
		_sea_near.extra_cull_margin = 4.0
		_sea_near.position.y = Terrain.sea_level
		add_child(_sea_near)
		_sea_far = MeshInstance3D.new()
		_sea_far.name = "sea_far"
		_sea_far.mesh = _disc(SEA_FAR_RADIUS, SEA_FAR_STEP)
		_sea_far.mesh.surface_set_material(0, _material(Vector2.ZERO))
		_sea_far.position.y = Terrain.sea_level - 0.15
		add_child(_sea_far)
	for w in Terrain.water_bodies:
		var center: Vector2 = w.center
		var mi := MeshInstance3D.new()
		mi.name = String(w.id)
		mi.mesh = _disc(float(w.radius))
		mi.mesh.surface_set_material(0, _material(Vector2.ZERO))
		mi.extra_cull_margin = 2.0  # waves leave the flat AABB
		mi.position = Vector3(center.x,
				float(w.surface) + Terrain.lake_levels[w.idx], center.y)
		add_child(mi)
		_lake_meshes[w.id] = mi
	for r in Terrain.rivers:
		var mi := MeshInstance3D.new()
		mi.name = String(r.id)
		# Rivers flow by their per-vertex map (UV2), not the whole-mesh
		# drift: direction lives in the mesh, speed in flow_scale.
		var mat := _material(Vector2.ZERO)
		mat.set_shader_parameter("rapids_boost", 1.0)
		mat.set_shader_parameter("flow_scale", _flow_speed(r.id))
		mi.mesh = _ribbon(r.nodes, Terrain.river_levels[r.idx], float(r.depth))
		_river_built_level[r.id] = Terrain.river_levels[r.idx]
		mi.mesh.surface_set_material(0, mat)
		mi.extra_cull_margin = 2.0
		add_child(mi)
		_river_meshes[r.id] = mi
		_river_mats[r.id] = mat
	Hydrology.levels_changed.connect(_on_levels_changed)


func _process(_delta: float) -> void:
	# In map view the terrain's elevation palette IS the water (teal
	# seabed) — hide the pink surface meshes so it reads consistently
	# at every zoom (the near sea disc doesn't reach the region rim).
	if MapScreen.active:
		if visible:
			hide()
		return
	if not visible:
		show()
	if _sea_near == null:
		return
	var focus := Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player")
	if GodMode.active:
		var p := GodMode.cam_position()
		focus = Vector2(p.x, p.z)
	elif MapScreen.active:
		var p := MapScreen.focus_position()
		focus = Vector2(p.x, p.z)
	elif player:
		focus = Vector2(player.global_position.x, player.global_position.z)
	# Snapped so the wave-sampling verts don't shimmer as the focus moves.
	var snapped_focus := focus.snappedf(SEA_NEAR_STEP * 2.0)
	_sea_near.position.x = snapped_focus.x
	_sea_near.position.z = snapped_focus.y
	# The tide: both sheets ride the live surface, and the strand
	# shader's dark band follows it via the sea_level global.
	var live: float = Terrain.sea_surface()
	_sea_near.position.y = live
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


func _material(flow: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("flow", flow)
	return mat


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


# A dense ribbon: the spline resampled every RIBBON_STEP meters with
# RIBBON_ACROSS verts per cross-section. World-space (seam-free with the
# pond under the shared world-reading shader).
# The DRAPE (2026-07-05): record nodes carry one surface each and the
# terrain undulates between them, so a node-lerped surface either floats
# over dips or bridges spurs. Instead every row takes
# min(node-lerped surface, carved centerline ground + depth) — identical
# to the record waterline on normal spans (the carve puts the bed
# exactly depth below it), but following the terrain down through dips —
# then a backward max-scan from the mouth makes the surface monotone
# downstream, pooling flat behind lips instead of running uphill.
# Steep row-to-row drops are written into COLOR.r → shader rapids foam.
func _ribbon(nodes: Array, level: float, depth: float) -> ArrayMesh:
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
	# Drape, then pool: the max-scan can only raise a row toward the
	# record waterlines upstream of it, so the surface stays inside the
	# carved channel everywhere (record surfaces are monotone downstream).
	var surf := PackedFloat32Array(); surf.resize(rows.size())
	for i in rows.size():
		var p: Vector2 = rows[i][0]
		surf[i] = minf(rows[i][2], Terrain.height(p.x, p.y) + depth)
	for i in range(rows.size() - 2, -1, -1):
		surf[i] = maxf(surf[i], surf[i + 1])
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
	# Rapids strength from the local grade (COLOR.r → shader foam).
	var rapids := PackedFloat32Array(); rapids.resize(final_rows.size())
	for i in final_rows.size():
		var drop := 0.0
		if i < final_rows.size() - 1:
			drop = float(final_rows[i][2]) - float(final_rows[i + 1][2])
		rapids[i] = smoothstep(0.06, 0.30, drop / RIBBON_STEP)
	# Emit rows of verts, stitch quads. UV2 is the FLOW MAP: downstream
	# direction × a local pace (rapids race, pools laze) — the shader
	# advects ripples and foam along it, scaled by the live discharge.
	for i in final_rows.size():
		var row: Array = final_rows[i]
		var perp: Vector2 = Vector2(-row[3].y, row[3].x)
		st.set_color(Color(rapids[i], 0.0, 0.0))
		var tan_v: Vector2 = row[3]
		st.set_uv2(tan_v * (0.7 + 1.8 * rapids[i]))
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
