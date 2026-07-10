#include "contour_kernel.h"
#include "lattice_embed.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <chrono>
#include <vector>

using namespace godot;

// --- marshalling: Godot Variant <-> LatValue ------------------------------
// The vector components ride as double but represent real_t/float32; the Swift
// side narrows on the way in and widens on the way out, so bit-parity holds.

static bool variant_to_lat(const Variant &v, LatValue &out) {
	out = LatValue{};
	switch (v.get_type()) {
		case Variant::INT:    out.tag = LAT_INT;   out.i = (int64_t)v; return true;
		case Variant::FLOAT:  out.tag = LAT_FLOAT; out.f = (double)v;  return true;
		case Variant::BOOL:   out.tag = LAT_BOOL;  out.i = ((bool)v) ? 1 : 0; return true;
		case Variant::VECTOR2: {
			Vector2 p = v; out.tag = LAT_VEC2; out.x = p.x; out.y = p.y; return true;
		}
		case Variant::VECTOR3: {
			Vector3 p = v; out.tag = LAT_VEC3; out.x = p.x; out.y = p.y; out.z = p.z; return true;
		}
		default: return false;
	}
}

static Variant lat_to_variant(const LatValue &v) {
	switch (v.tag) {
		case LAT_INT:   return Variant((int64_t)v.i);
		case LAT_FLOAT: return Variant(v.f);
		case LAT_BOOL:  return Variant(v.i != 0);
		case LAT_VEC2:  return Variant(Vector2((real_t)v.x, (real_t)v.y));
		case LAT_VEC3:  return Variant(Vector3((real_t)v.x, (real_t)v.y, (real_t)v.z));
		case LAT_NULL:  return Variant();
		default:        return Variant(); // LAT_ERR
	}
}

ContourKernel::~ContourKernel() {
	if (handle) { lattice_module_destroy(handle); handle = nullptr; }
}

String ContourKernel::load_module(const String &src) {
	if (handle) { lattice_module_destroy(handle); handle = nullptr; }
	CharString utf8 = src.utf8();
	char err[1024] = {0};
	handle = lattice_module_create(utf8.get_data(), (int64_t)utf8.length(), err, sizeof(err));
	if (!handle) return String(err);
	return String();
}

Variant ContourKernel::contour_call(const String &fn, const Array &args) {
	if (!handle) return Variant();
	std::vector<LatValue> argv;
	argv.reserve(args.size());
	for (int i = 0; i < args.size(); i++) {
		LatValue lv;
		if (!variant_to_lat(args[i], lv)) {
			UtilityFunctions::push_error("contour_call: unmarshalable arg ", i);
			return Variant();
		}
		argv.push_back(lv);
	}
	CharString fname = fn.utf8();
	LatValue out{};
	char err[1024] = {0};
	int rc = lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(),
			&out, err, sizeof(err));
	if (rc != 0) { UtilityFunctions::push_error("contour_call: ", String(err)); return Variant(); }
	return lat_to_variant(out);
}

Dictionary ContourKernel::bench(const String &fn, const Array &args, int64_t iters) {
	Dictionary d;
	if (!handle || iters <= 0) { d["ok"] = false; return d; }
	std::vector<LatValue> argv;
	argv.reserve(args.size());
	for (int i = 0; i < args.size(); i++) {
		LatValue lv;
		if (!variant_to_lat(args[i], lv)) { d["ok"] = false; return d; }
		argv.push_back(lv);
	}
	CharString fname = fn.utf8();
	LatValue out{};
	char err[1024] = {0};
	// Warm once (compile is already done; this primes caches/branch predictors).
	lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(), &out, err, sizeof(err));

	auto t0 = std::chrono::steady_clock::now();
	int bad = 0;
	for (int64_t k = 0; k < iters; k++) {
		if (lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(),
				&out, err, sizeof(err)) != 0) bad++;
	}
	auto t1 = std::chrono::steady_clock::now();
	double total_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
	d["ok"] = (bad == 0);
	d["total_us"] = total_us;
	d["per_call_us"] = total_us / (double)iters;
	d["result"] = lat_to_variant(out);
	return d;
}

Dictionary ContourKernel::bench_marshal(const String &fn, const Array &args, int64_t iters) {
	Dictionary d;
	if (!handle || iters <= 0) { d["ok"] = false; return d; }
	CharString fname = fn.utf8();
	char err[1024] = {0};
	LatValue out{};
	auto t0 = std::chrono::steady_clock::now();
	int bad = 0;
	for (int64_t k = 0; k < iters; k++) {
		std::vector<LatValue> argv;
		argv.reserve(args.size());
		for (int i = 0; i < args.size(); i++) {
			LatValue lv; variant_to_lat(args[i], lv); argv.push_back(lv);
		}
		if (lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(),
				&out, err, sizeof(err)) != 0) bad++;
	}
	auto t1 = std::chrono::steady_clock::now();
	double total_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
	d["ok"] = (bad == 0);
	d["total_us"] = total_us;
	d["per_call_us"] = total_us / (double)iters;
	return d;
}

void ContourKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_module", "src"), &ContourKernel::load_module);
	ClassDB::bind_method(D_METHOD("is_loaded"), &ContourKernel::is_loaded);
	ClassDB::bind_method(D_METHOD("contour_call", "fn", "args"), &ContourKernel::contour_call);
	ClassDB::bind_method(D_METHOD("bench", "fn", "args", "iters"), &ContourKernel::bench);
	ClassDB::bind_method(D_METHOD("bench_marshal", "fn", "args", "iters"), &ContourKernel::bench_marshal);
}
