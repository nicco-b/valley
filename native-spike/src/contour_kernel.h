// ContourKernel — the embed-spike GDExtension (Mission Z2, PLAN_ENGINE §3 E2).
//
// A thin godot-cpp wrapper over the datum LatticeEmbed C ABI (lattice_embed.h):
// it compiles a Contour module once (load_module) and calls a function per
// invocation (contour_call), marshalling Godot Variants <-> the flat LatValue
// wire. This is "shape (a)": Swift static archive + C ABI + a C++ GDExtension,
// the Lattice VM running IN the game process on the game's own thread.
//
// PROBE ONLY — not wired into framework.json. It proves the shape links, runs,
// answers bit-identically to GDScript, and measures per-call overhead. The
// shipping wrapper would live beside native/ and be built by the same chain.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class ContourKernel : public RefCounted {
	GDCLASS(ContourKernel, RefCounted)

	void *handle = nullptr;   // opaque LatticeEmbed module handle

protected:
	static void _bind_methods();

public:
	ContourKernel() = default;
	~ContourKernel();

	// Compile a Contour module from source. Returns "" on success, else the
	// diagnostic. COLD — call once at load.
	String load_module(const String &src);
	bool is_loaded() const { return handle != nullptr; }

	// Call `fn` with `args` (int/float/bool/Vector2/Vector3), marshalling the
	// result back to a Variant. Returns null on error. HOT.
	Variant contour_call(const String &fn, const Array &args);

	// Bench the PURE VM path: marshal args once, loop the C-ABI call `iters`
	// times, return {per_call_us, total_us, ok, result}. Isolates VM+ABI cost.
	Dictionary bench(const String &fn, const Array &args, int64_t iters);

	// Bench the FULL path: re-marshal Variant->LatValue every iteration (what
	// a real contour_call from the tick pays). {per_call_us, total_us}.
	Dictionary bench_marshal(const String &fn, const Array &args, int64_t iters);
};

} // namespace godot
