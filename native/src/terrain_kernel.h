// TerrainKernel — the Loom's C++ hot path (GDExtension).
// Bit-exact port of terrain.gd's height() / water_surface_base() plus
// block/mesh builders, so worker threads never execute GDScript (the
// descent-crash class: GDScript VM corruption under the streamer's
// concurrent sampling — see docs/STATUS.md "OPEN BLOCKER").
// Determinism contract: doubles where GDScript used float, engine
// Vector2/Vector3 (real_t) where GDScript used them, the SAME
// FastNoiseLite instances and edit-layer Image, -ffp-contract=off.
// Configured once from Terrain._ready; immutable afterwards (worker
// threads call concurrently).
#pragma once

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <vector>

namespace godot {

class TerrainKernel : public RefCounted {
	GDCLASS(TerrainKernel, RefCounted)

	// Base landform (mirrors terrain.gd constants + noises).
	Ref<FastNoiseLite> hills, dunes, ranges, island, coast;
	Ref<Image> edits;
	double edit_size = 2048.0;
	double edit_m_per_px = 2.0;
	PackedFloat64Array flattens; // x, z, radius, feather per disk
	PackedVector2Array valley_path;
	double valley_inner = 120.0, valley_outer = 220.0, wall_height = 42.0;

	// Home guard + sea.
	Vector2 home_pos, home_end;
	double guard_in = 150.0, guard_out = 550.0;
	double sea_level = -1e12, seabed = -35.0;

	// Lakes.
	PackedVector2Array lake_center;
	PackedFloat64Array lake_radius, lake_surface, lake_basin_r, lake_basin_d;

	// Rivers (indexed like terrain.gd _index_river).
	struct River {
		PackedVector2Array seg_a, seg_ab;
		PackedFloat32Array seg_inv_l2, seg_half, seg_surf;
		Rect2 bbox;
		std::vector<PackedInt32Array> grid;
		int grid_w = 0;
		double depth = 1.2, feather = 4.0, margin = 18.0, grid_step = 32.0;
	};
	std::vector<River> rivers;

	// Painted tiles (F3): heightmap rect replaces procedural ground.
	struct Tile {
		double x0 = 0, z0 = 0, size = 1, feather = 100, hmin = 0, hmax = 1;
		int res = 0;
		PackedFloat32Array data;
	};
	std::vector<Tile> tiles;
	double tile_blend(double x, double z, double h, double guard) const;

	// Regions (the archipelago; packed mirrors of terrain.gd).
	PackedInt32Array reg_kind;
	PackedFloat32Array reg_bbox, reg_radius, reg_reach, reg_inner,
			reg_height, reg_tiers, reg_coast_amp, reg_coast_freq,
			reg_ridges, reg_ridge_depth;
	PackedInt32Array reg_over_bay;
	PackedFloat32Array reg_peak_amp, reg_peak_len;
	double coast_wobble(double x, double z, double amp, double freq) const;
	PackedVector2Array reg_center;
	std::vector<PackedVector2Array> reg_nodes;

	// Bays: subtractive sea-reach carve (after landforms).
	PackedVector2Array bay_center;
	PackedFloat32Array bay_radius, bay_feather, bay_floor, bay_amp, bay_freq;
	double bay_carve(double x, double z, double h, double guard) const;

	Vector3 river_probe(const River &r, double x, double z) const;
	double region_height(double x, double z, int over_bay_phase) const;
	double edit_height(double x, double z) const;

protected:
	static void _bind_methods();

public:
	void set_base(const Ref<FastNoiseLite> &p_hills,
			const Ref<FastNoiseLite> &p_dunes,
			const Ref<FastNoiseLite> &p_ranges,
			const Ref<FastNoiseLite> &p_island, const Ref<Image> &p_edits,
			double p_edit_size, double p_edit_m_per_px,
			const PackedFloat64Array &p_flattens,
			const PackedVector2Array &p_valley_path, double p_inner,
			double p_outer, double p_wall_height);
	void set_home(const Vector2 &p_pos, const Vector2 &p_end, double p_in,
			double p_out, double p_sea, double p_seabed);
	void set_lakes(const PackedVector2Array &p_center,
			const PackedFloat64Array &p_radius,
			const PackedFloat64Array &p_surface,
			const PackedFloat64Array &p_basin_r,
			const PackedFloat64Array &p_basin_d);
	void add_river(const Dictionary &p_river);
	void set_regions(const PackedInt32Array &p_kind,
			const PackedFloat32Array &p_bbox,
			const PackedVector2Array &p_center,
			const PackedFloat32Array &p_radius,
			const PackedFloat32Array &p_reach,
			const PackedFloat32Array &p_inner,
			const PackedFloat32Array &p_height,
			const PackedFloat32Array &p_tiers, const Array &p_nodes,
			const PackedFloat32Array &p_coast_amp,
			const PackedFloat32Array &p_coast_freq,
			const PackedFloat32Array &p_ridges,
			const PackedFloat32Array &p_ridge_depth,
			const PackedInt32Array &p_over_bay,
			const PackedFloat32Array &p_peak_amp,
			const PackedFloat32Array &p_peak_len);
	void set_coast(const Ref<FastNoiseLite> &p_coast);
	void set_bays(const PackedVector2Array &p_center,
			const PackedFloat32Array &p_radius,
			const PackedFloat32Array &p_feather,
			const PackedFloat32Array &p_floor,
			const PackedFloat32Array &p_amp,
			const PackedFloat32Array &p_freq);
	void set_tiles(const Array &p_tiles);

	double home_guard(double x, double z) const;
	double height(double x, double z) const;
	double water_surface_base(double x, double z) const;

	// Bulk samplers (row-major nz rows of nx).
	PackedFloat32Array height_block(double ox, double oz, double step,
			int nx, int nz) const;
	PackedFloat32Array water_base_block(double ox, double oz, double step,
			int nx, int nz) const;
	// Full cell mesh: vertices (cell-local), normals, uvs (world*0.05),
	// indices, wet flags, pts (cell-local, for nav faces).
	Dictionary build_cell(double ox, double oz, double cell_size, int res,
			bool with_wet) const;
	// Far-LOD sheet: world-space vertices sunk by p_sink, normals,
	// indices; p_skirt > 0 adds a perimeter skirt dropped by that many
	// meters (hides cracks between quadtree LOD levels).
	Dictionary build_far(double ox, double oz, double size, int res,
			double sink, double skirt) const;
	Dictionary debug_parts(double x, double z) const;

	// The bake (map pipeline stage A): painted elevation guide ->
	// believable terrain. Bilinear upsample + fractal relief +
	// thermal talus + hydraulic droplet erosion (the believability
	// engine: coherent drainage, alluvial fans, sediment). Seeded,
	// deterministic. Returns the eroded heightfield (out_res^2,
	// meters); params tune droplet count/strength/talus.
	// Returns {"height": PackedFloat32Array(out^2, meters),
	//          "flow":   PackedFloat32Array(out^2, droplet passage)}.
	// The flow map is the drainage network the erosion carved — Stage C
	// traces rivers from it.
	Dictionary bake_terrain(const PackedFloat32Array &p_guide,
			int p_guide_res, double p_world_size, int p_out_res,
			int p_seed, const Dictionary &p_params) const;
};

} // namespace godot
