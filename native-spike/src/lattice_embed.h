/* lattice_embed.h — the C ABI for embedding the Lattice VM in a host process.
 *
 * PLAN_ENGINE §3 E2, the embed spike (Mission Z2). This is the surface a
 * godot-cpp GDExtension (or any C/C++ host) links against to run a compiled
 * Contour module inside the host's own process — no sidecar, the host owns the
 * tick. The header is pure C (no Swift, no Foundation), stable across the ABI
 * boundary; the implementation is @_cdecl Swift over the Lattice package.
 *
 * Lifecycle:
 *   handle = lattice_module_create(src, len, err, errcap);   // COLD: compile once
 *   lattice_call(handle, "fn", argv, argc, &out, err, errcap);// HOT: per tick
 *   lattice_module_destroy(handle);
 *
 * Determinism: the hot path (lattice_call) marshals values by tag through the
 * Lattice interpreter and touches no wall-clock, no RNG, no Foundation. The
 * cold path (compile) uses Foundation (the lexer/parser) — off the tick.
 *
 * Threading: a handle is NOT re-entrant (the interpreter carries a frame
 * stack). One handle per calling thread, or serialize calls. The valley sim
 * tick is single-threaded, so one handle on the tick thread is the model.
 */
#ifndef LATTICE_EMBED_H
#define LATTICE_EMBED_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Value tags — mirror Lattice.Value's scalar + vector kinds. Composite kinds
 * (array/dict/basis) are NOT yet marshalled across the C ABI: a function that
 * returns one yields LAT_ERR with a message (see the report's "first landing
 * rung"). cycle_grid_step / snap_to_grid / ground_normal / aligned_basis*
 * are all covered by scalars + vec2/vec3 (+ basis, below). */
#define LAT_INT   0  /* i */
#define LAT_FLOAT 1  /* f */
#define LAT_BOOL  2  /* i (0/1) */
#define LAT_VEC2  3  /* x, y  (components are float32/real_t, widened to double here) */
#define LAT_VEC3  4  /* x, y, z */
#define LAT_NULL  5
#define LAT_ERR   6  /* result-only: call failed; see err buffer */

/* A tagged scalar/vector on the wire. Vector components are carried as double
 * but represent Godot real_t (float32): the Swift side narrows on the way in
 * (matching Vector3(double,double,double)) and widens on the way out (matching
 * reading v.x as a Variant float), so bit-parity with GDScript is preserved. */
typedef struct {
    int32_t tag;
    int64_t i;
    double  f;
    double  x, y, z;
} LatValue;

/* Compile a Contour module from UTF-8 source. Returns an opaque handle, or
 * NULL on a compile error (err receives a NUL-terminated diagnostic, truncated
 * to errcap). COLD path — do this once at load, never on the tick. */
void *lattice_module_create(const char *src, int64_t len, char *err, int32_t errcap);

/* Release a handle created by lattice_module_create. NULL is a no-op. */
void lattice_module_destroy(void *handle);

/* Call `fn` with argc LatValues; write the result into *out.
 * Returns 0 on success. On failure returns non-zero, sets out->tag = LAT_ERR,
 * and writes a NUL-terminated message to err (truncated to errcap).
 * HOT path — no allocation beyond the interpreter's own, no Foundation. */
int32_t lattice_call(void *handle, const char *fn,
                     const LatValue *argv, int32_t argc,
                     LatValue *out, char *err, int32_t errcap);

#ifdef __cplusplus
}
#endif

#endif /* LATTICE_EMBED_H */
