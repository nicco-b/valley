#include "contour_kernel.h"
#include "lattice_embed.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <chrono>
#include <cstring>
#include <vector>

using namespace godot;

// --- marshalling: Godot Variant <-> LatValue ------------------------------
// Scalars/vec2/vec3 ride the flat LatValue fields; the vector components cross
// as double but represent real_t/float32 (the Swift side narrows in, widens
// out) so bit-parity holds. COMPOSITES (Array/Dictionary/Basis) cross as a
// LAT_BUF: a CompositeCodec byte buffer. The byte layout is owned by
// lattice_embed.h (the single source of truth); the encoder/decoder below
// implement that table, preserving the SAME Float32<->Double boundary the
// scalar vec3 path uses (a vec2/vec3/basis component widens on encode, narrows
// on decode; a plain float is a full double).

// CompositeCodec element tags (see lattice_embed.h).
enum : uint8_t {
	CC_INT = 0x00, CC_FLOAT = 0x01, CC_BOOL = 0x02, CC_STR = 0x03,
	CC_ARRAY = 0x04, CC_DICT = 0x05, CC_VEC2 = 0x06, CC_VEC3 = 0x07,
	CC_BASIS = 0x08, CC_RECORD = 0x09, CC_NULL = 0x0a,
};

// ---- encode: Variant -> CompositeCodec bytes (little-endian) --------------
static void cc_u32(std::vector<uint8_t> &o, uint32_t v) {
	o.push_back((uint8_t)(v & 0xff));       o.push_back((uint8_t)((v >> 8) & 0xff));
	o.push_back((uint8_t)((v >> 16) & 0xff)); o.push_back((uint8_t)((v >> 24) & 0xff));
}
static void cc_u64(std::vector<uint8_t> &o, uint64_t v) {
	for (int i = 0; i < 8; i++) { o.push_back((uint8_t)(v & 0xff)); v >>= 8; }
}
static void cc_double(std::vector<uint8_t> &o, double d) {
	uint64_t bits; std::memcpy(&bits, &d, 8); cc_u64(o, bits);   // 8 LE IEEE-754 bytes
}
static void cc_str(std::vector<uint8_t> &o, const String &s) {
	CharString u = s.utf8();
	cc_u32(o, (uint32_t)u.length());
	const char *p = u.get_data();
	for (int i = 0; i < u.length(); i++) o.push_back((uint8_t)p[i]);
}
static void cc_pairs(std::vector<uint8_t> &o, const Dictionary &d);

static void cc_encode(std::vector<uint8_t> &o, const Variant &v) {
	switch (v.get_type()) {
		case Variant::INT:   o.push_back(CC_INT);   cc_u64(o, (uint64_t)(int64_t)v); break;
		case Variant::FLOAT: o.push_back(CC_FLOAT); cc_double(o, (double)v); break;
		case Variant::BOOL:  o.push_back(CC_BOOL);  o.push_back(((bool)v) ? 1 : 0); break;
		case Variant::STRING:
		case Variant::STRING_NAME: o.push_back(CC_STR); cc_str(o, (String)v); break;
		case Variant::VECTOR2: { Vector2 p = v; o.push_back(CC_VEC2); cc_double(o, p.x); cc_double(o, p.y); break; }
		case Variant::VECTOR3: { Vector3 p = v; o.push_back(CC_VEC3); cc_double(o, p.x); cc_double(o, p.y); cc_double(o, p.z); break; }
		case Variant::BASIS: {
			Basis b = v; o.push_back(CC_BASIS);
			// COLUMN order (x,y,z axes) — get_column(i) is the i-th axis.
			for (int c = 0; c < 3; c++) { Vector3 col = b.get_column(c); cc_double(o, col.x); cc_double(o, col.y); cc_double(o, col.z); }
			break;
		}
		case Variant::ARRAY: {
			Array a = v; o.push_back(CC_ARRAY); cc_u32(o, (uint32_t)a.size());
			for (int i = 0; i < a.size(); i++) cc_encode(o, a[i]);
			break;
		}
		case Variant::DICTIONARY: { o.push_back(CC_DICT); cc_pairs(o, (Dictionary)v); break; }
		case Variant::NIL: o.push_back(CC_NULL); break;
		default:
			// Packed arrays etc. would go here if a port needed them; not on the
			// twelve. Encode as NULL rather than corrupt the stream.
			o.push_back(CC_NULL); break;
	}
}
static void cc_pairs(std::vector<uint8_t> &o, const Dictionary &d) {
	Array keys = d.keys();
	cc_u32(o, (uint32_t)keys.size());   // insertion order (Godot Dictionary preserves it)
	for (int i = 0; i < keys.size(); i++) { cc_encode(o, keys[i]); cc_encode(o, d[keys[i]]); }
}

// ---- decode: CompositeCodec bytes -> Variant ------------------------------
struct CCReader { const uint8_t *b; size_t len; size_t off; bool ok; };
static uint32_t ccr_u32(CCReader &r) {
	if (r.off + 4 > r.len) { r.ok = false; return 0; }
	uint32_t v = (uint32_t)r.b[r.off] | ((uint32_t)r.b[r.off+1] << 8) | ((uint32_t)r.b[r.off+2] << 16) | ((uint32_t)r.b[r.off+3] << 24);
	r.off += 4; return v;
}
static uint64_t ccr_u64(CCReader &r) {
	if (r.off + 8 > r.len) { r.ok = false; return 0; }
	uint64_t v = 0; for (int i = 0; i < 8; i++) v |= (uint64_t)r.b[r.off+i] << (8*i);
	r.off += 8; return v;
}
static double ccr_double(CCReader &r) { uint64_t bits = ccr_u64(r); double d; std::memcpy(&d, &bits, 8); return d; }
static String ccr_str(CCReader &r) {
	uint32_t n = ccr_u32(r);
	if (!r.ok || r.off + n > r.len) { r.ok = false; return String(); }
	String s = String::utf8((const char *)(r.b + r.off), (int64_t)n);
	r.off += n; return s;
}
static Variant cc_decode(CCReader &r) {
	if (r.off + 1 > r.len) { r.ok = false; return Variant(); }
	uint8_t tag = r.b[r.off++];
	switch (tag) {
		case CC_INT:   return Variant((int64_t)ccr_u64(r));
		case CC_FLOAT: return Variant(ccr_double(r));
		case CC_BOOL:  if (r.off + 1 > r.len) { r.ok = false; return Variant(); } return Variant(r.b[r.off++] != 0);
		case CC_STR:   return Variant(ccr_str(r));
		case CC_VEC2:  { double x = ccr_double(r), y = ccr_double(r); return Variant(Vector2((real_t)x, (real_t)y)); }   // NARROW
		case CC_VEC3:  { double x = ccr_double(r), y = ccr_double(r), z = ccr_double(r); return Variant(Vector3((real_t)x, (real_t)y, (real_t)z)); }
		case CC_BASIS: {
			double c[9]; for (int i = 0; i < 9; i++) c[i] = ccr_double(r);   // column-major x,y,z axes
			// Basis(x_axis, y_axis, z_axis) sets COLUMNS — symmetric with encode.
			return Variant(Basis(Vector3((real_t)c[0], (real_t)c[1], (real_t)c[2]),
			                     Vector3((real_t)c[3], (real_t)c[4], (real_t)c[5]),
			                     Vector3((real_t)c[6], (real_t)c[7], (real_t)c[8])));
		}
		case CC_ARRAY: {
			uint32_t n = ccr_u32(r); Array a;
			for (uint32_t i = 0; i < n && r.ok; i++) a.push_back(cc_decode(r));
			return a;
		}
		case CC_DICT: {
			uint32_t n = ccr_u32(r); Dictionary d;
			for (uint32_t i = 0; i < n && r.ok; i++) { Variant k = cc_decode(r); Variant vv = cc_decode(r); d[k] = vv; }
			return d;
		}
		case CC_RECORD: {
			// A record decodes to a Dictionary tagged with its schema name under
			// "__record__" — no ported function returns one, but the boundary
			// carries it faithfully (unknown keys + order preserved).
			String name = ccr_str(r);
			uint32_t n = ccr_u32(r); Dictionary d;
			for (uint32_t i = 0; i < n && r.ok; i++) { Variant k = cc_decode(r); Variant vv = cc_decode(r); d[k] = vv; }
			d["__record__"] = name;
			return d;
		}
		case CC_NULL: return Variant();
		default: r.ok = false; return Variant();
	}
}

// A scalar/vector arg fills the flat fields; a composite arg is encoded into
// `store` (which the caller keeps alive across the call) and referenced by buf.
static void marshal_arg(const Variant &v, LatValue &out, std::vector<uint8_t> &store) {
	out = LatValue{};
	switch (v.get_type()) {
		case Variant::INT:    out.tag = LAT_INT;   out.i = (int64_t)v; return;
		case Variant::FLOAT:  out.tag = LAT_FLOAT; out.f = (double)v;  return;
		case Variant::BOOL:   out.tag = LAT_BOOL;  out.i = ((bool)v) ? 1 : 0; return;
		case Variant::VECTOR2: { Vector2 p = v; out.tag = LAT_VEC2; out.x = p.x; out.y = p.y; return; }
		case Variant::VECTOR3: { Vector3 p = v; out.tag = LAT_VEC3; out.x = p.x; out.y = p.y; out.z = p.z; return; }
		case Variant::NIL:    out.tag = LAT_NULL; return;
		default:
			cc_encode(store, v);
			out.tag = LAT_BUF; out.buf = store.data(); out.buflen = (int64_t)store.size();
			return;
	}
}

// Marshal an argument Array into argv, keeping composite backing buffers alive
// in `bufs` (reserved so no realloc invalidates a buf pointer already stored).
static void marshal_args(const Array &args, std::vector<LatValue> &argv, std::vector<std::vector<uint8_t>> &bufs) {
	bufs.clear(); bufs.reserve(args.size());
	argv.clear(); argv.reserve(args.size());
	for (int i = 0; i < args.size(); i++) {
		bufs.emplace_back();
		LatValue lv;
		marshal_arg(args[i], lv, bufs.back());
		argv.push_back(lv);
	}
}

// Decode a result LatValue into a Variant. A LAT_BUF result is Lattice-owned;
// the caller frees it via lattice_buf_free AFTER this returns its decoded copy.
static Variant lat_to_variant(const LatValue &v) {
	switch (v.tag) {
		case LAT_INT:   return Variant((int64_t)v.i);
		case LAT_FLOAT: return Variant(v.f);
		case LAT_BOOL:  return Variant(v.i != 0);
		case LAT_VEC2:  return Variant(Vector2((real_t)v.x, (real_t)v.y));
		case LAT_VEC3:  return Variant(Vector3((real_t)v.x, (real_t)v.y, (real_t)v.z));
		case LAT_NULL:  return Variant();
		case LAT_BUF: {
			if (!v.buf) return Variant();
			CCReader r{v.buf, (size_t)v.buflen, 0, true};
			Variant out = cc_decode(r);
			return r.ok ? out : Variant();
		}
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
	std::vector<std::vector<uint8_t>> bufs;   // backing storage for composite args
	marshal_args(args, argv, bufs);
	CharString fname = fn.utf8();
	LatValue out{};
	char err[1024] = {0};
	int rc = lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(),
			&out, err, sizeof(err));
	if (rc != 0) { UtilityFunctions::push_error("contour_call: ", String(err)); return Variant(); }
	Variant result = lat_to_variant(out);
	if (out.tag == LAT_BUF) lattice_buf_free(out.buf);   // Lattice-owned result buffer
	return result;
}

Dictionary ContourKernel::bench(const String &fn, const Array &args, int64_t iters) {
	Dictionary d;
	if (!handle || iters <= 0) { d["ok"] = false; return d; }
	std::vector<LatValue> argv;
	std::vector<std::vector<uint8_t>> bufs;   // composite args marshalled ONCE (pure-VM path)
	marshal_args(args, argv, bufs);
	CharString fname = fn.utf8();
	LatValue out{};
	char err[1024] = {0};
	// Warm once (compile is already done; this primes caches/branch predictors).
	lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(), &out, err, sizeof(err));
	if (out.tag == LAT_BUF) lattice_buf_free(out.buf);

	auto t0 = std::chrono::steady_clock::now();
	int bad = 0;
	for (int64_t k = 0; k < iters; k++) {
		if (lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(),
				&out, err, sizeof(err)) != 0) bad++;
		// Free each iteration's result buffer (a composite-returning bench would
		// otherwise leak one buffer per call).
		if (out.tag == LAT_BUF) { lattice_buf_free(out.buf); out.buf = nullptr; }
	}
	auto t1 = std::chrono::steady_clock::now();
	double total_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
	// One more call to capture a live result for reporting, then free it.
	lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(), &out, err, sizeof(err));
	d["ok"] = (bad == 0);
	d["total_us"] = total_us;
	d["per_call_us"] = total_us / (double)iters;
	d["result"] = lat_to_variant(out);
	if (out.tag == LAT_BUF) lattice_buf_free(out.buf);
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
		// Re-marshal every iteration (what a real contour_call from the tick pays,
		// now including composite-arg encode).
		std::vector<LatValue> argv;
		std::vector<std::vector<uint8_t>> bufs;
		marshal_args(args, argv, bufs);
		if (lattice_call(handle, fname.get_data(), argv.data(), (int32_t)argv.size(),
				&out, err, sizeof(err)) != 0) bad++;
		if (out.tag == LAT_BUF) { lattice_buf_free(out.buf); out.buf = nullptr; }
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
