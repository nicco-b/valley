#include "terrain_kernel.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

// GDScript float is double; mirror Math::smoothstep/lerp (double).
static inline double gd_smoothstep(double from, double to, double s) {
	return Math::smoothstep(from, to, s);
}

static inline double gd_lerp(double a, double b, double t) {
	return a + t * (b - a);
}

void TerrainKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_base", "hills", "dunes", "ranges",
								  "island", "edits", "edit_size",
								  "edit_m_per_px", "flattens", "valley_path",
								  "inner", "outer", "wall_height"),
			&TerrainKernel::set_base);
	ClassDB::bind_method(D_METHOD("set_home", "pos", "end", "in", "out",
								  "sea", "seabed"),
			&TerrainKernel::set_home);
	ClassDB::bind_method(D_METHOD("set_lakes", "center", "radius", "surface",
								  "basin_r", "basin_d"),
			&TerrainKernel::set_lakes);
	ClassDB::bind_method(D_METHOD("add_river", "river"),
			&TerrainKernel::add_river);
	ClassDB::bind_method(D_METHOD("set_regions", "kind", "bbox", "center",
								  "radius", "reach", "inner", "height",
								  "tiers", "nodes"),
			&TerrainKernel::set_regions);
	ClassDB::bind_method(D_METHOD("home_guard", "x", "z"),
			&TerrainKernel::home_guard);
	ClassDB::bind_method(D_METHOD("height", "x", "z"),
			&TerrainKernel::height);
	ClassDB::bind_method(D_METHOD("water_surface_base", "x", "z"),
			&TerrainKernel::water_surface_base);
	ClassDB::bind_method(D_METHOD("height_block", "ox", "oz", "step", "nx",
								  "nz"),
			&TerrainKernel::height_block);
	ClassDB::bind_method(D_METHOD("water_base_block", "ox", "oz", "step",
								  "nx", "nz"),
			&TerrainKernel::water_base_block);
	ClassDB::bind_method(D_METHOD("build_cell", "ox", "oz", "cell_size",
								  "res", "with_wet"),
			&TerrainKernel::build_cell);
	ClassDB::bind_method(D_METHOD("set_tiles", "tiles"),
			&TerrainKernel::set_tiles);
	ClassDB::bind_method(D_METHOD("build_far", "ox", "oz", "size", "res",
								  "sink", "skirt"),
			&TerrainKernel::build_far);
	ClassDB::bind_method(D_METHOD("debug_parts", "x", "z"),
			&TerrainKernel::debug_parts);
}

void TerrainKernel::set_base(const Ref<FastNoiseLite> &p_hills,
		const Ref<FastNoiseLite> &p_dunes, const Ref<FastNoiseLite> &p_ranges,
		const Ref<FastNoiseLite> &p_island, const Ref<Image> &p_edits,
		double p_edit_size, double p_edit_m_per_px,
		const PackedFloat64Array &p_flattens,
		const PackedVector2Array &p_valley_path, double p_inner,
		double p_outer, double p_wall_height) {
	hills = p_hills;
	dunes = p_dunes;
	ranges = p_ranges;
	island = p_island;
	edits = p_edits;
	edit_size = p_edit_size;
	edit_m_per_px = p_edit_m_per_px;
	flattens = p_flattens;
	valley_path = p_valley_path;
	valley_inner = p_inner;
	valley_outer = p_outer;
	wall_height = p_wall_height;
}

void TerrainKernel::set_home(const Vector2 &p_pos, const Vector2 &p_end,
		double p_in, double p_out, double p_sea, double p_seabed) {
	home_pos = p_pos;
	home_end = p_end;
	guard_in = p_in;
	guard_out = p_out;
	sea_level = p_sea;
	seabed = p_seabed;
}

void TerrainKernel::set_lakes(const PackedVector2Array &p_center,
		const PackedFloat64Array &p_radius,
		const PackedFloat64Array &p_surface,
		const PackedFloat64Array &p_basin_r,
		const PackedFloat64Array &p_basin_d) {
	lake_center = p_center;
	lake_radius = p_radius;
	lake_surface = p_surface;
	lake_basin_r = p_basin_r;
	lake_basin_d = p_basin_d;
}

void TerrainKernel::add_river(const Dictionary &p_river) {
	River r;
	r.seg_a = p_river["seg_a"];
	r.seg_ab = p_river["seg_ab"];
	r.seg_inv_l2 = p_river["seg_inv_l2"];
	r.seg_half = p_river["seg_half"];
	r.seg_surf = p_river["seg_surf"];
	r.bbox = p_river["bbox"];
	r.grid_w = (int)p_river["grid_w"];
	r.depth = (double)p_river["depth"];
	r.feather = (double)p_river["feather"];
	Array grid = p_river["grid"];
	r.grid.reserve(grid.size());
	for (int i = 0; i < grid.size(); i++) {
		r.grid.push_back(PackedInt32Array(grid[i]));
	}
	rivers.push_back(r);
}

void TerrainKernel::set_regions(const PackedInt32Array &p_kind,
		const PackedFloat32Array &p_bbox, const PackedVector2Array &p_center,
		const PackedFloat32Array &p_radius, const PackedFloat32Array &p_reach,
		const PackedFloat32Array &p_inner, const PackedFloat32Array &p_height,
		const PackedFloat32Array &p_tiers, const Array &p_nodes) {
	reg_kind = p_kind;
	reg_bbox = p_bbox;
	reg_center = p_center;
	reg_radius = p_radius;
	reg_reach = p_reach;
	reg_inner = p_inner;
	reg_height = p_height;
	reg_tiers = p_tiers;
	reg_nodes.clear();
	reg_nodes.reserve(p_nodes.size());
	for (int i = 0; i < p_nodes.size(); i++) {
		reg_nodes.push_back(PackedVector2Array(p_nodes[i]));
	}
}

void TerrainKernel::set_tiles(const Array &p_tiles) {
	tiles.clear();
	tiles.reserve(p_tiles.size());
	for (int i = 0; i < p_tiles.size(); i++) {
		Dictionary d = p_tiles[i];
		Tile t;
		t.x0 = (double)d["x0"];
		t.z0 = (double)d["z0"];
		t.size = (double)d["size"];
		t.feather = (double)d["feather"];
		t.hmin = (double)d["hmin"];
		t.hmax = (double)d["hmax"];
		t.res = (int)d["res"];
		t.data = d["data"];
		tiles.push_back(t);
	}
}

// Mirrors terrain.gd _tile_blend (painted heightmap replaces ground).
double TerrainKernel::tile_blend(double x, double z, double h,
		double guard) const {
	for (const Tile &t : tiles) {
		if (x < t.x0 || z < t.z0 || x >= t.x0 + t.size ||
				z >= t.z0 + t.size) {
			continue;
		}
		const float *data = t.data.ptr();
		double px = (x - t.x0) / t.size * (t.res - 1);
		double pz = (z - t.z0) / t.size * (t.res - 1);
		int ix = Math::min((int)px, t.res - 2);
		int iz = Math::min((int)pz, t.res - 2);
		double fx = px - ix;
		double fz = pz - iz;
		double v = gd_lerp(
				gd_lerp((double)data[iz * t.res + ix],
						(double)data[iz * t.res + ix + 1], fx),
				gd_lerp((double)data[(iz + 1) * t.res + ix],
						(double)data[(iz + 1) * t.res + ix + 1], fx),
				fz);
		double target = t.hmin + v * (t.hmax - t.hmin);
		double edge = Math::min(
				Math::min(x - t.x0, t.x0 + t.size - x),
				Math::min(z - t.z0, t.z0 + t.size - z));
		double w = gd_smoothstep(0.0, t.feather, edge) * guard;
		h = gd_lerp(h, target, w);
	}
	return h;
}

// Mirrors terrain.gd _river_probe exactly (Vector2/Vector3 real_t math).
Vector3 TerrainKernel::river_probe(const River &r, double x, double z) const {
	static const Vector3 FAR_ANSWER(1e12f, 0.0f, -1e12f);
	const Rect2 &bbox = r.bbox;
	if (x < bbox.position.x || z < bbox.position.y ||
			x >= bbox.position.x + bbox.size.x ||
			z >= bbox.position.y + bbox.size.y) {
		return FAR_ANSWER;
	}
	int gx = (int)((x - bbox.position.x) / r.grid_step);
	int gz = (int)((z - bbox.position.y) / r.grid_step);
	const PackedInt32Array &candidates = r.grid[gz * r.grid_w + gx];
	if (candidates.is_empty()) {
		return FAR_ANSWER;
	}
	Vector2 p(x, z);
	Vector3 best = FAR_ANSWER;
	const Vector2 *seg_a = r.seg_a.ptr();
	const Vector2 *seg_ab = r.seg_ab.ptr();
	const float *seg_inv_l2 = r.seg_inv_l2.ptr();
	const float *seg_half = r.seg_half.ptr();
	const float *seg_surf = r.seg_surf.ptr();
	for (int ci = 0; ci < candidates.size(); ci++) {
		int i = candidates[ci];
		Vector2 rel = p - seg_a[i];
		double t = Math::clamp(
				(double)rel.dot(seg_ab[i]) * (double)seg_inv_l2[i], 0.0, 1.0);
		double d = rel.distance_to(seg_ab[i] * (real_t)t);
		if (d < best.x) {
			best = Vector3(d,
					gd_lerp((double)seg_half[i], (double)seg_half[i + 1], t),
					gd_lerp((double)seg_surf[i], (double)seg_surf[i + 1], t));
		}
	}
	return best;
}

double TerrainKernel::region_height(double x, double z) const {
	Vector2 p(x, z);
	double total = 0.0;
	double detail = 1e12; // sentinel: noise not yet sampled
	const int32_t *kinds = reg_kind.ptr();
	const float *bbox = reg_bbox.ptr();
	for (int i = 0; i < reg_kind.size(); i++) {
		int b = i * 4;
		if (x < (double)bbox[b] || z < (double)bbox[b + 1] ||
				x >= (double)bbox[b + 2] || z >= (double)bbox[b + 3]) {
			continue;
		}
		int kind = kinds[i];
		double env;
		if (kind == 2) { // ridge
			const PackedVector2Array &nodes = reg_nodes[i];
			double d = 1e12;
			for (int s = 0; s < nodes.size() - 1; s++) {
				Vector2 a = nodes[s];
				Vector2 ab = nodes[s + 1] - a;
				double t = Math::clamp(
						(double)(p - a).dot(ab) / (double)ab.length_squared(),
						0.0, 1.0);
				d = Math::min(d, (double)p.distance_to(a + ab * (real_t)t));
			}
			if (d >= (double)reg_reach[i]) {
				continue;
			}
			env = 1.0 - gd_smoothstep((double)reg_inner[i],
							  (double)reg_reach[i], d);
			env = env * env * (3.0 - 2.0 * env);
		} else {
			double d = p.distance_to(reg_center[i]);
			if (d >= (double)reg_reach[i]) {
				continue;
			}
			env = 1.0 - gd_smoothstep((double)reg_radius[i] * 0.35,
							  (double)reg_reach[i], d);
			if (kind == 0) { // mesa: rounded-riser terraces
				double t = env * (double)reg_tiers[i];
				double stepped =
						(Math::floor(t) +
								gd_smoothstep(0.15, 0.85, t - Math::floor(t))) /
						(double)reg_tiers[i];
				env = gd_lerp(env, stepped, 0.7);
			}
		}
		if (detail == 1e12) {
			detail = island->get_noise_2d(x, z);
		}
		total += (double)reg_height[i] * (env + detail * 0.06 * env);
	}
	return total;
}

double TerrainKernel::edit_height(double x, double z) const {
	double half = edit_size * edit_m_per_px * 0.5;
	double px = (x + half) / edit_m_per_px;
	double pz = (z + half) / edit_m_per_px;
	if (px < 0.0 || pz < 0.0 || px >= edit_size - 1 || pz >= edit_size - 1) {
		return 0.0;
	}
	int ix = (int)px;
	int iz = (int)pz;
	double fx = px - ix;
	double fz = pz - iz;
	double h00 = edits->get_pixel(ix, iz).r;
	double h10 = edits->get_pixel(ix + 1, iz).r;
	double h01 = edits->get_pixel(ix, iz + 1).r;
	double h11 = edits->get_pixel(ix + 1, iz + 1).r;
	return gd_lerp(gd_lerp(h00, h10, fx), gd_lerp(h01, h11, fx), fz);
}

double TerrainKernel::home_guard(double x, double z) const {
	double gdx = Math::max(
			Math::max((double)home_pos.x - x, x - (double)home_end.x), 0.0);
	double gdz = Math::max(
			Math::max((double)home_pos.y - z, z - (double)home_end.y), 0.0);
	double wobble = hills->get_noise_2d(x * 2.0, z * 2.0) * 120.0;
	return gd_smoothstep(guard_in + wobble, guard_out + wobble,
			Math::sqrt(gdx * gdx + gdz * gdz));
}

double TerrainKernel::height(double x, double z) const {
	double hills_n = hills->get_noise_2d(x, z);
	double floor_h = hills_n * 3.0 + dunes->get_noise_2d(x, z) * 0.6;
	double wall_h = wall_height + hills_n * 22.0;
	// valley_factor
	Vector2 p(x, z);
	double d = 1e12;
	for (int i = 0; i < valley_path.size() - 1; i++) {
		Vector2 a = valley_path[i];
		Vector2 ab = valley_path[i + 1] - a;
		double t = Math::clamp(
				(double)(p - a).dot(ab) / (double)ab.length_squared(), 0.0,
				1.0);
		d = Math::min(d, (double)p.distance_to(a + ab * (real_t)t));
	}
	double vf = gd_smoothstep(valley_inner, valley_outer, d);
	double h = gd_lerp(floor_h, wall_h, vf);
	double range_envelope = gd_smoothstep(1200.0, 2400.0, Vector2(x, z).length());
	double range_term =
			Math::max(ranges->get_noise_2d(x, z), 0.0f) * 320.0 * range_envelope;
	double guard = home_guard(x, z);
	if (guard > 0.0) {
		double sb = seabed + hills_n * 4.0 + dunes->get_noise_2d(x, z) * 1.5;
		h = gd_lerp(h, sb, guard);
		range_term *= 1.0 - guard;
		h += region_height(x, z) * guard;
	}
	h += range_term;
	if (!tiles.empty() && guard > 0.0) {
		h = tile_blend(x, z, h, guard);
	}
	const double *fl = flattens.ptr();
	for (int i = 0; i + 3 < flattens.size(); i += 4) {
		double fd = Vector2(x - (double)fl[i], z - (double)fl[i + 1]).length();
		h *= gd_smoothstep((double)fl[i + 2],
				(double)fl[i + 2] + (double)fl[i + 3], fd);
	}
	for (int i = 0; i < lake_center.size(); i++) {
		Vector2 c = lake_center[i];
		double ld = Vector2(x - (double)c.x, z - (double)c.y).length();
		h -= (double)lake_basin_d[i] *
				gd_smoothstep(1.0, 0.0, ld / (double)lake_basin_r[i]);
	}
	for (const River &r : rivers) {
		Vector3 q = river_probe(r, x, z);
		double half = q.y;
		if (q.x > half + r.feather) {
			continue;
		}
		double target;
		if (q.x <= half) {
			target = gd_lerp((double)q.z - r.depth, (double)q.z,
					(double)q.x / Math::max(half, 1e-4));
		} else {
			target = gd_lerp((double)q.z, h, ((double)q.x - half) / r.feather);
		}
		h = Math::min(h, target);
	}
	return h + edit_height(x, z);
}

Dictionary TerrainKernel::debug_parts(double x, double z) const {
	Dictionary out;
	double hills_n = hills->get_noise_2d(x, z);
	out["hills"] = hills_n;
	out["dunes"] = (double)dunes->get_noise_2d(x, z);
	double floor_h = hills_n * 3.0 + dunes->get_noise_2d(x, z) * 0.6;
	double wall_h = wall_height + hills_n * 22.0;
	Vector2 p(x, z);
	double d = 1e12;
	for (int i = 0; i < valley_path.size() - 1; i++) {
		Vector2 a = valley_path[i];
		Vector2 ab = valley_path[i + 1] - a;
		double t = Math::clamp(
				(double)(p - a).dot(ab) / (double)ab.length_squared(), 0.0,
				1.0);
		d = Math::min(d, (double)p.distance_to(a + ab * (real_t)t));
	}
	out["valley_d"] = d;
	out["vf"] = gd_smoothstep(valley_inner, valley_outer, d);
	out["floor_h"] = floor_h;
	out["wall_h"] = wall_h;
	out["ranges"] = (double)ranges->get_noise_2d(x, z);
	return out;
}

double TerrainKernel::water_surface_base(double x, double z) const {
	for (int i = 0; i < lake_center.size(); i++) {
		Vector2 c = lake_center[i];
		if (Vector2(x - (double)c.x, z - (double)c.y).length() <
				(double)lake_radius[i]) {
			return (double)lake_surface[i];
		}
	}
	for (const River &r : rivers) {
		Vector3 q = river_probe(r, x, z);
		if (q.x < q.y) {
			return q.z;
		}
	}
	if (sea_level > -1e11 && home_guard(x, z) > 0.0) {
		return sea_level;
	}
	return -1e12;
}

PackedFloat32Array TerrainKernel::height_block(double ox, double oz,
		double step, int nx, int nz) const {
	PackedFloat32Array out;
	out.resize(nx * nz);
	float *w = out.ptrw();
	for (int iz = 0; iz < nz; iz++) {
		for (int ix = 0; ix < nx; ix++) {
			w[iz * nx + ix] = height(ox + ix * step, oz + iz * step);
		}
	}
	return out;
}

PackedFloat32Array TerrainKernel::water_base_block(double ox, double oz,
		double step, int nx, int nz) const {
	PackedFloat32Array out;
	out.resize(nx * nz);
	float *w = out.ptrw();
	for (int iz = 0; iz < nz; iz++) {
		for (int ix = 0; ix < nx; ix++) {
			double s = water_surface_base(ox + ix * step, oz + iz * step);
			w[iz * nx + ix] = s < -1e11 ? -1e12f : (float)s;
		}
	}
	return out;
}

Dictionary TerrainKernel::build_cell(double ox, double oz, double cell_size,
		int res, bool with_wet) const {
	double step = cell_size / (res - 1);
	PackedVector3Array vertices;
	vertices.resize(res * res);
	PackedVector2Array uvs;
	uvs.resize(res * res);
	PackedByteArray wet;
	wet.resize(res * res);
	Vector3 *vw = vertices.ptrw();
	Vector2 *uw = uvs.ptrw();
	uint8_t *ww = wet.ptrw();
	for (int iz = 0; iz < res; iz++) {
		for (int ix = 0; ix < res; ix++) {
			double wx = ox + ix * step;
			double wz = oz + iz * step;
			double y = height(wx, wz);
			int i = iz * res + ix;
			vw[i] = Vector3(ix * step, y, iz * step);
			uw[i] = Vector2(wx, wz) * (real_t)0.05;
			ww[i] = (with_wet && y < water_surface_base(wx, wz) - 0.05) ? 1
																		: 0;
		}
	}
	PackedInt32Array indices;
	indices.resize((res - 1) * (res - 1) * 6);
	int32_t *iw = indices.ptrw();
	int n = 0;
	for (int iz = 0; iz < res - 1; iz++) {
		for (int ix = 0; ix < res - 1; ix++) {
			int i = iz * res + ix;
			iw[n++] = i;
			iw[n++] = i + 1;
			iw[n++] = i + res;
			iw[n++] = i + 1;
			iw[n++] = i + res + 1;
			iw[n++] = i + res;
		}
	}
	// Smooth normals: accumulate face normals per vertex (what
	// SurfaceTool.generate_normals does for one smooth group).
	PackedVector3Array normals;
	normals.resize(res * res);
	Vector3 *nw = normals.ptrw();
	for (int i = 0; i < indices.size(); i += 3) {
		const Vector3 &a = vw[iw[i]];
		const Vector3 &b = vw[iw[i + 1]];
		const Vector3 &c = vw[iw[i + 2]];
		Vector3 fn = (c - a).cross(b - a);
		nw[iw[i]] += fn;
		nw[iw[i + 1]] += fn;
		nw[iw[i + 2]] += fn;
	}
	for (int i = 0; i < normals.size(); i++) {
		nw[i] = nw[i].normalized();
	}
	Dictionary out;
	out["vertices"] = vertices;
	out["normals"] = normals;
	out["uvs"] = uvs;
	out["indices"] = indices;
	out["wet"] = wet;
	return out;
}

Dictionary TerrainKernel::build_far(double ox, double oz, double size,
		int res, double sink, double skirt) const {
	double step = size / (res - 1);
	int body = res * res;
	int skirt_verts = skirt > 0.0 ? res * 4 : 0;
	PackedVector3Array vertices;
	vertices.resize(body + skirt_verts);
	Vector3 *vw = vertices.ptrw();
	for (int iz = 0; iz < res; iz++) {
		for (int ix = 0; ix < res; ix++) {
			double wx = ox + ix * step;
			double wz = oz + iz * step;
			vw[iz * res + ix] = Vector3(wx, height(wx, wz) - sink, wz);
		}
	}
	if (skirt > 0.0) {
		// Perimeter duplicated and dropped: north, south, west, east.
		for (int i = 0; i < res; i++) {
			vw[body + i] = vw[i] + Vector3(0, -skirt, 0);
			vw[body + res + i] = vw[(res - 1) * res + i] + Vector3(0, -skirt, 0);
			vw[body + res * 2 + i] = vw[i * res] + Vector3(0, -skirt, 0);
			vw[body + res * 3 + i] = vw[i * res + res - 1] + Vector3(0, -skirt, 0);
		}
	}
	int quads = (res - 1) * (res - 1) + (skirt > 0.0 ? (res - 1) * 4 : 0);
	PackedInt32Array indices;
	indices.resize(quads * 6);
	int32_t *iw = indices.ptrw();
	int n = 0;
	for (int iz = 0; iz < res - 1; iz++) {
		for (int ix = 0; ix < res - 1; ix++) {
			int i = iz * res + ix;
			iw[n++] = i;
			iw[n++] = i + 1;
			iw[n++] = i + res;
			iw[n++] = i + 1;
			iw[n++] = i + res + 1;
			iw[n++] = i + res;
		}
	}
	if (skirt > 0.0) {
		for (int i = 0; i < res - 1; i++) {
			// North edge (z = oz): top verts i..i+1, skirt below.
			iw[n++] = i; iw[n++] = body + i + 1; iw[n++] = body + i;
			iw[n++] = i; iw[n++] = i + 1; iw[n++] = body + i + 1;
			// South edge.
			int s0 = (res - 1) * res + i;
			iw[n++] = s0; iw[n++] = body + res + i; iw[n++] = body + res + i + 1;
			iw[n++] = s0; iw[n++] = body + res + i + 1; iw[n++] = s0 + 1;
			// West edge (x = ox).
			int w0 = i * res;
			iw[n++] = w0; iw[n++] = body + res * 2 + i; iw[n++] = body + res * 2 + i + 1;
			iw[n++] = w0; iw[n++] = body + res * 2 + i + 1; iw[n++] = w0 + res;
			// East edge.
			int e0 = i * res + res - 1;
			iw[n++] = e0; iw[n++] = body + res * 3 + i + 1; iw[n++] = body + res * 3 + i;
			iw[n++] = e0; iw[n++] = e0 + res; iw[n++] = body + res * 3 + i + 1;
		}
	}
	PackedVector3Array normals;
	normals.resize(vertices.size()); // body + skirt (skirt tris index past res*res)
	Vector3 *nw = normals.ptrw();
	for (int i = 0; i < indices.size(); i += 3) {
		const Vector3 &a = vw[iw[i]];
		const Vector3 &b = vw[iw[i + 1]];
		const Vector3 &c = vw[iw[i + 2]];
		Vector3 fn = (c - a).cross(b - a);
		nw[iw[i]] += fn;
		nw[iw[i + 1]] += fn;
		nw[iw[i + 2]] += fn;
	}
	for (int i = 0; i < normals.size(); i++) {
		nw[i] = nw[i].normalized();
	}
	Dictionary out;
	out["vertices"] = vertices;
	out["normals"] = normals;
	out["indices"] = indices;
	return out;
}
