// ContourKernel — the production Contour-embed GDExtension (PLAN_ENGINE §3 E2).
//
// A thin godot-cpp wrapper over the datum LatticeEmbed C ABI (lattice_embed.h):
// it compiles a Contour module once (load_module) and calls a function per
// invocation (contour_call), marshalling Godot Variants <-> the flat LatValue
// wire. This is "shape (a)": Swift static archive + C ABI + a C++ GDExtension,
// the Lattice VM running IN the game process on the game's own thread.
//
// The graduation of native-spike/'s certified probe wrapper: identical
// marshalling (88/88 corpus bit-parity to GDScript), now built by the SAME
// CMake discipline as loomkernel (native/contour/, add_subdirectory(godot-cpp),
// template_debug AND template_release) and carried by framework.json. It is
// content-empty-safe and macOS-gated: the load site is a NO-OP when the dylib
// is absent (stock / other-platform games keep working), and nothing on the
// sim tick calls it unless a game opts in — so it is soak-inert while unused.
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

	// Advance the whole §6/§7 SYSTEM schedule one clock step of `dt` seconds over
	// `world` (a Dictionary of dotted resource -> value). Returns the resulting
	// world Dictionary (declared writes + reserved time.*/<System>.__time keys
	// riding in it, per lattice_tick's contract), or an EMPTY Dictionary on error.
	// HOT — the sim-tick surface (contour_call is the ported-function surface).
	Dictionary contour_tick(const Dictionary &world, double dt);

	// Report the module's SYSTEM manifest: an Array (declaration order) of
	// {name, reads, writes, timed} dictionaries, so a host seeds declared reads
	// and applies declared writes HONESTLY. Empty Array if no module is loaded.
	// COLD — read once after compile.
	Array contour_systems();

	// Bench the PURE VM path: marshal args once, loop the C-ABI call `iters`
	// times, return {per_call_us, total_us, ok, result}. Isolates VM+ABI cost.
	Dictionary bench(const String &fn, const Array &args, int64_t iters);

	// Bench the FULL path: re-marshal Variant->LatValue every iteration (what
	// a real contour_call from the tick pays). {per_call_us, total_us}.
	Dictionary bench_marshal(const String &fn, const Array &args, int64_t iters);
};

} // namespace godot
