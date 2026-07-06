# The Toolkit: the Blender terrain pipeline — open the world's elevation
# guide as sculptable geometry, edit it (and place kit objects), and
# write both back in the game's own formats. The guide stays the source
# of truth; the in-game bake (fractal relief + hydraulic erosion) keeps
# authoring the detail on top of whatever is sculpted here.
#
# Usage (from the repo root; see README.md beside this file):
#   blender -b --python assets/blender/terrain/valley_terrain.py -- import
#       builds assets/blender/terrain/valley_map.blend from
#       data/world/elevation_guide.exr + data/cells/*.json
#   blender -b assets/blender/terrain/valley_map.blend \
#       --python assets/blender/terrain/valley_terrain.py -- export
#       writes the guide EXR back + data/cells/cell_X_Y.json placements
#   blender -b --python assets/blender/terrain/valley_terrain.py -- test
#       headless round-trip self-check (used before committing changes here)
#
# Inside the Blender UI: open this file in the Scripting tab and Run —
# it imports if the scene is empty, exports if the terrain is present.
#
# Conventions (the asset contract, ASSETS_NEEDED.md):
#   scale 1:10 (SCALE below) · Blender +X = world +X · Blender +Y =
#   world -Z (north up in top view) · placements live in the
#   "Placements" collection, object name = kit id (suffixes like .001
#   stripped), rotation Z = yaw, scale = uniform scale, exported with
#   snap:true so the baked terrain seats them.

import bpy
import json
import math
import os
import sys

import numpy as np
from mathutils.bvhtree import BVHTree

SCALE = 0.1  # Blender units per meter (1:10 — the island fits a viewport)
TERRAIN_NAME = "ValleyTerrain"
PLACEMENTS = "Placements"
PROXIES = "KitProxies"
CELL_SIZE = 128.0
# Kit proxy shapes: id -> (kind, height m). Cones for flora, cubes for rock.
KIT_PROXY = {
	"rock_large": ("cube", 2.2),
	"rock_med": ("cube", 1.2),
	"tree_silly": ("cone", 3.5),
	"tree_palm": ("cone", 4.6),
	"shrub": ("cone", 1.8),
}


def repo_root() -> str:
	scene = bpy.context.scene
	if "valley_repo" in scene:
		return scene["valley_repo"]
	here = os.path.dirname(os.path.abspath(__file__))
	return os.path.normpath(os.path.join(here, "..", "..", ".."))


def load_meta(root: str) -> dict:
	with open(os.path.join(root, "data", "world", "guide.json")) as f:
		return json.load(f)


def read_exr_pixels(path: str) -> tuple:
	"""Load an EXR through Blender; return (numpy HxW float32 R channel,
	top-down row order like Godot's Image), plus resolution."""
	img = bpy.data.images.load(path, check_existing=False)
	w, h = img.size
	buf = np.empty(w * h * img.channels, dtype=np.float32)
	img.pixels.foreach_get(buf)
	r = buf.reshape(h, w, img.channels)[:, :, 0]
	bpy.data.images.remove(img)
	return np.flipud(r).copy(), w  # Blender rows are bottom-up; flip to top-down


def write_exr(path: str, top_down: "np.ndarray") -> None:
	"""Write a single-channel float EXR (32-bit) in Godot's row order."""
	h, w = top_down.shape
	img = bpy.data.images.new("valley_guide_out", w, h, alpha=False,
			float_buffer=True, is_data=True)
	rgba = np.empty((h, w, 4), dtype=np.float32)
	flipped = np.flipud(top_down)
	for c in range(3):
		rgba[:, :, c] = flipped
	rgba[:, :, 3] = 1.0
	img.pixels.foreach_set(rgba.ravel())
	scene = bpy.context.scene
	s = scene.render.image_settings
	prev = (s.file_format, s.color_depth, s.color_mode)
	s.file_format = "OPEN_EXR"
	s.color_depth = "32"
	s.color_mode = "RGB"
	img.save_render(path, scene=scene)
	s.file_format, s.color_depth, s.color_mode = prev
	bpy.data.images.remove(img)


def _collection(name: str) -> "bpy.types.Collection":
	col = bpy.data.collections.get(name)
	if col is None:
		col = bpy.data.collections.new(name)
		bpy.context.scene.collection.children.link(col)
	return col


def _proxy_mesh(kit_id: str) -> "bpy.types.Mesh":
	name = "proxy_" + kit_id
	mesh = bpy.data.meshes.get(name)
	if mesh:
		return mesh
	kind, height_m = KIT_PROXY.get(kit_id, ("cube", 1.5))
	h = height_m * SCALE
	mesh = bpy.data.meshes.new(name)
	if kind == "cone":
		r = h * 0.35
		n = 8
		verts = [(r * math.cos(i * math.tau / n), r * math.sin(i * math.tau / n), 0.0)
				for i in range(n)] + [(0.0, 0.0, h)]
		faces = [(i, (i + 1) % n, n) for i in range(n)] + [tuple(range(n))]
	else:
		r = h * 0.5
		verts = [(sx * r, sy * r, sz * h * 0.5 + h * 0.5)
				for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
		faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4),
				(1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6)]
	mesh.from_pydata(verts, [], faces)
	mesh.update()
	return mesh


def _upsample_bilinear(a: "np.ndarray", out: int) -> "np.ndarray":
	n = a.shape[0]
	t = np.linspace(0.0, n - 1.0, out)
	i0 = np.clip(t.astype(np.int64), 0, n - 2)
	f = (t - i0).astype(np.float32)
	rows = a[i0] * (1.0 - f)[:, None] + a[i0 + 1] * f[:, None]
	cols = rows[:, i0] * (1.0 - f)[None, :] + rows[:, i0 + 1] * f[None, :]
	return cols.astype(np.float32)


def import_world(save_blend: bool = True, res_override: int = 0) -> None:
	root = repo_root()
	meta = load_meta(root)
	gmin = float(meta.get("guide_min", -60.0))
	gspan = float(meta.get("guide_max", 1000.0)) - gmin
	inv_gamma = 1.0 / float(meta.get("guide_gamma", 1.0))
	world = float(meta["world_size"])
	ox = float(meta["origin"]["x"])
	oz = float(meta["origin"]["z"])

	norm, res = read_exr_pixels(os.path.join(root, "data", "world", "elevation_guide.exr"))
	meters = gmin + np.power(np.clip(norm, 0.0, 1.0), inv_gamma) * gspan
	# Optional denser sculpt grid (-- import --res 2048): bilinear
	# upsample — no new information, but finer brush control; export
	# writes the guide back at whatever res the mesh carries (the bake
	# reads any width). Note the mesh shows the GUIDE: the game's
	# fractal relief + erosion detail is baked on top after export.
	if res_override and res_override != res:
		meters = _upsample_bilinear(meters, res_override)
		res = res_override
	step = world / res

	# The terrain: one vertex per guide pixel, heights baked into the
	# mesh (no modifier — sculpt acts on the real data).
	px = (ox + np.arange(res) * step) * SCALE
	py = -(oz + np.arange(res) * step) * SCALE  # Blender +Y = world -Z
	xx, yy = np.meshgrid(px, py)
	zz = meters * SCALE
	verts = np.stack([xx, yy, zz], axis=-1).reshape(-1, 3)
	idx = np.arange(res * res).reshape(res, res)
	quads = np.stack([idx[:-1, :-1], idx[:-1, 1:], idx[1:, 1:], idx[1:, :-1]],
			axis=-1).reshape(-1, 4)
	mesh = bpy.data.meshes.new(TERRAIN_NAME)
	mesh.from_pydata(verts.tolist(), [], quads.tolist())
	# Smooth shading: flat-shaded 16m quads read far coarser than the
	# data is; smoothing shows the actual landform.
	mesh.polygons.foreach_set("use_smooth", np.ones(len(mesh.polygons), dtype=bool))
	mesh.update()
	obj = bpy.data.objects.new(TERRAIN_NAME, mesh)
	bpy.context.scene.collection.objects.link(obj)
	obj.lock_location = obj.lock_rotation = obj.lock_scale = (True, True, True)

	bvh = None  # built lazily for placement display heights
	place_col = _collection(PLACEMENTS)
	proxy_col = _collection(PROXIES)
	proxy_col.hide_viewport = True
	proxy_col.hide_render = True
	cells_dir = os.path.join(root, "data", "cells")
	count = 0
	if os.path.isdir(cells_dir):
		depsgraph = bpy.context.evaluated_depsgraph_get()
		bvh = BVHTree.FromObject(obj, depsgraph)
		for fname in sorted(os.listdir(cells_dir)):
			if not fname.endswith(".json"):
				continue
			with open(os.path.join(cells_dir, fname)) as f:
				records = json.load(f)
			for rec in records:
				kit = str(rec.get("kit", ""))
				mesh_p = _proxy_mesh(kit)
				if mesh_p.name not in [o.data.name for o in proxy_col.objects]:
					tmpl = bpy.data.objects.new("tmpl_" + kit, mesh_p)
					proxy_col.objects.link(tmpl)
				p = bpy.data.objects.new(kit, mesh_p)
				x = float(rec["x"]) * SCALE
				y = -float(rec["z"]) * SCALE
				z = float(rec.get("y", 0.0)) * SCALE
				if rec.get("snap", False) and bvh:
					hit = bvh.ray_cast((x, y, 1e5), (0, 0, -1))
					if hit[0] is not None:
						z = hit[0].z
				p.location = (x, y, z)
				p.rotation_euler = (0.0, 0.0, float(rec.get("yaw", 0.0)))
				s = float(rec.get("scale", 1.0))
				p.scale = (s, s, s)
				if "day" in rec:
					p["day"] = int(rec["day"])
				place_col.objects.link(p)
				count += 1

	scene = bpy.context.scene
	scene["valley_repo"] = root
	scene["valley_meta"] = json.dumps(meta)
	print("valley import: %d^2 terrain, %d placements" % (res, count))
	if save_blend:
		path = os.path.join(root, "assets", "blender", "terrain", "valley_map.blend")
		bpy.ops.wm.save_as_mainfile(filepath=path)
		print("valley import: saved", path)


def export_world(guide_out: str = "", cells_out: str = "") -> dict:
	root = repo_root()
	meta = json.loads(bpy.context.scene.get("valley_meta", "null")) or load_meta(root)
	gmin = float(meta.get("guide_min", -60.0))
	gspan = float(meta.get("guide_max", 1000.0)) - gmin
	gamma = float(meta.get("guide_gamma", 1.0))
	world = float(meta["world_size"])
	ox = float(meta["origin"]["x"])
	oz = float(meta["origin"]["z"])

	obj = bpy.data.objects.get(TERRAIN_NAME)
	if obj is None:
		raise RuntimeError("no %s object in this scene" % TERRAIN_NAME)
	res = int(round(math.sqrt(len(obj.data.vertices))))
	step = world / res

	# Start from the vertices by index (exact where sculpting only moved
	# heights), then overlay top-down ray samples at the guide grid —
	# those win wherever they connect, making the export robust to
	# grab/relax strokes that slide vertices sideways and flattening
	# accidental overhangs (the heightfield law, applied here). Rays
	# that graze the mesh boundary miss by epsilon; the index heights
	# already cover them.
	co = np.empty(res * res * 3, dtype=np.float32)
	obj.data.vertices.foreach_get("co", co)
	meters = (co.reshape(res, res, 3)[:, :, 2] / SCALE).astype(np.float32)
	depsgraph = bpy.context.evaluated_depsgraph_get()
	bvh = BVHTree.FromObject(obj, depsgraph)
	for pz in range(res):
		y = -(oz + pz * step) * SCALE
		row = meters[pz]
		for px_i in range(res):
			x = (ox + px_i * step) * SCALE
			hit = bvh.ray_cast((x, y, 1e5), (0, 0, -1))
			if hit[0] is not None:
				row[px_i] = hit[0].z / SCALE
	norm = np.power(np.clip((meters - gmin) / gspan, 0.0, 1.0), gamma)

	guide_path = guide_out or os.path.join(root, "data", "world", "elevation_guide.exr")
	write_exr(guide_path, norm.astype(np.float32))
	print("valley export: guide ->", guide_path)

	# Placements: everything in the Placements collection, grouped into
	# the game's cell files. Cells emptied in Blender are NOT deleted on
	# disk (safety) — remove stale cell_X_Y.json by hand.
	cells: dict = {}
	col = bpy.data.collections.get(PLACEMENTS)
	skipped = 0
	if col:
		for p in col.objects:
			kit = p.name.split(".")[0]
			if kit not in KIT_PROXY:
				skipped += 1
				continue
			wx = p.location.x / SCALE
			wz = -p.location.y / SCALE
			cell = (int(round(wx / CELL_SIZE)), int(round(wz / CELL_SIZE)))
			cells.setdefault(cell, []).append({
				"kit": kit,
				"x": round(wx, 2), "y": 0.0, "z": round(wz, 2),
				"yaw": round(p.rotation_euler.z % math.tau, 3),
				"scale": round(sum(p.scale) / 3.0, 3),
				"snap": True,
				"day": int(p.get("day", 0)),
			})
	out_dir = cells_out or os.path.join(root, "data", "cells")
	os.makedirs(out_dir, exist_ok=True)
	for cell, records in sorted(cells.items()):
		path = os.path.join(out_dir, "cell_%d_%d.json" % cell)
		with open(path, "w") as f:
			f.write(json.dumps(records, indent="\t"))
	n = sum(len(v) for v in cells.values())
	print("valley export: %d placements into %d cell files%s" % (
		n, len(cells), " (%d skipped: unknown kit id)" % skipped if skipped else ""))
	return {"cells": len(cells), "placements": n, "res": res}


def _test() -> None:
	"""Headless self-check: import, add a known placement, export to a
	scratch dir, and require the untouched guide to round-trip."""
	import tempfile
	root = repo_root()
	import_world(save_blend=False)
	# A rock at a known spot, as if set-dressed in Blender.
	p = bpy.data.objects.new("rock_large", _proxy_mesh("rock_large"))
	p.location = ((100.0) * SCALE, -(-300.0) * SCALE, 0.0)
	p.rotation_euler = (0.0, 0.0, 1.5)
	bpy.data.collections[PLACEMENTS].objects.link(p)

	tmp = tempfile.mkdtemp(prefix="valley_bl_test_")
	guide_out = os.path.join(tmp, "guide.exr")
	stats = export_world(guide_out=guide_out, cells_out=tmp)

	orig, res_a = read_exr_pixels(os.path.join(root, "data", "world", "elevation_guide.exr"))
	trip, res_b = read_exr_pixels(guide_out)
	err = float(np.max(np.abs(orig - trip)))
	# Full-float EXR + exact grid resampling: the only error is float
	# math; half-float storage anywhere in the chain would show as ~5e-4.
	ok_err = err < 2e-3
	# The pond cells are already authored, so the test rock shares its
	# file with real imported records — search for it.
	cell_path = os.path.join(tmp, "cell_1_-2.json")  # round(100/128), round(-300/128)
	rec = {}
	if os.path.exists(cell_path):
		for r in json.load(open(cell_path)):
			if r.get("kit") == "rock_large" and abs(r.get("x", 0) - 100.0) < 0.01:
				rec = r
	ok_rec = rec.get("kit") == "rock_large" and abs(rec.get("z", 0) + 300.0) < 0.01 \
		and rec.get("snap") is True and abs(rec.get("yaw", 0) - 1.5) < 0.01
	print("TEST guide round-trip max err: %.2e (%s)" % (err, "ok" if ok_err else "FAIL"))
	print("TEST placement record: %s" % ("ok" if ok_rec else "FAIL %s" % rec))
	if ok_err and ok_rec and stats["placements"] >= 1:
		print("VALLEY BLENDER PIPELINE TEST PASS")
	else:
		print("VALLEY BLENDER PIPELINE TEST FAIL")
		sys.exit(1)


def _main() -> None:
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	mode = argv[0] if argv else ("export" if bpy.data.objects.get(TERRAIN_NAME) else "import")
	res_override = int(argv[argv.index("--res") + 1]) if "--res" in argv else 0
	if mode == "import":
		import_world(res_override=res_override)
	elif mode == "export":
		export_world()
	elif mode == "test":
		_test()
	else:
		raise SystemExit("unknown mode: " + mode)


_main()
