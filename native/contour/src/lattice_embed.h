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
 *   lattice_systems(handle, &out, err, errcap);              // COLD: read the manifest
 *   lattice_call(handle, "fn", argv, argc, &out, err, errcap);// HOT: per tick (a fn)
 *   lattice_tick(handle, world, worldlen, dt, &out, ...);    // HOT: per tick (systems)
 *   lattice_module_destroy(handle);
 *
 * Two hot entries: lattice_call runs one exported function (the ported-function
 * surface); lattice_tick advances the whole §6/§7 SYSTEM schedule one clock step
 * against a world dict — the sim-tick surface. lattice_systems reports each
 * system's DECLARED reads/writes so a host can seed and apply honestly (declared
 * access only). All three are deterministic and Foundation-free.
 *
 * Determinism: the hot path (lattice_call / lattice_tick) marshals values by tag
 * through the Lattice interpreter and touches no wall-clock, no RNG, no
 * Foundation. The cold path (compile) uses Foundation (the lexer/parser) — off
 * the tick.
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

/* Value tags — mirror Lattice.Value's scalar + vector kinds. Scalars and
 * vec2/vec3 ride the flat fields below; the COMPOSITE kinds (array / dict /
 * basis / record) cross as a LAT_BUF: a length-prefixed byte buffer in the
 * CompositeCodec wire format (documented at the bottom of this file — the
 * single source of truth for the layout). Before the composite-marshalling
 * rung a composite result yielded LAT_ERR; now every one of the twelve ported
 * functions is callable, composite args and composite results included.
 * A bare top-level STRING result crosses as LAT_STR: raw UTF-8 bytes in
 * buf/buflen (NOT NUL-terminated, NOT CompositeCodec-framed) — the same
 * ownership rules as a LAT_BUF result. (A string ARG still rides a LAT_BUF
 * as a top-level CC_STR — the shape existing hosts already send.) */
#define LAT_INT   0  /* i */
#define LAT_FLOAT 1  /* f */
#define LAT_BOOL  2  /* i (0/1) */
#define LAT_VEC2  3  /* x, y  (components are float32/real_t, widened to double here) */
#define LAT_VEC3  4  /* x, y, z */
#define LAT_NULL  5
#define LAT_ERR   6  /* result-only: call failed; see err buffer */
#define LAT_BUF   7  /* composite (array/dict/basis/record): buf + buflen, see below */
#define LAT_STR   8  /* result-only: bare string; buf + buflen = raw UTF-8 (no NUL) */

/* A tagged value on the wire. Scalars use `i`/`f`; vec2/vec3 use `x,y,z`
 * (components are double but represent Godot real_t/float32 — the Swift side
 * narrows on the way in, matching Vector3(double,double,double), and widens on
 * the way out, matching reading v.x as a Variant float, so bit-parity with
 * GDScript is preserved). A LAT_BUF carries a CompositeCodec byte buffer in
 * `buf` (length `buflen`); a LAT_STR result carries raw UTF-8 bytes in the
 * same two fields; the flat scalar/vector fields are then unused. */
typedef struct {
    int32_t tag;
    int64_t i;
    double  f;
    double  x, y, z;
    const uint8_t *buf;    /* LAT_BUF: CompositeCodec bytes (format at file end); LAT_STR: raw UTF-8 */
    int64_t        buflen; /* LAT_BUF / LAT_STR only: byte count of `buf` */
} LatValue;

/* Free a LAT_BUF or LAT_STR buffer that lattice_call allocated for a *result*
 * (out->buf). NULL is a no-op. See the OWNERSHIP note on lattice_call. */
void lattice_buf_free(const uint8_t *buf);

/* Compile a Contour module from UTF-8 source. Returns an opaque handle, or
 * NULL on a compile error (err receives a NUL-terminated diagnostic, truncated
 * to errcap). COLD path — do this once at load, never on the tick. */
void *lattice_module_create(const char *src, int64_t len, char *err, int32_t errcap);

/* Release a handle created by lattice_module_create. NULL is a no-op. */
void lattice_module_destroy(void *handle);

/* Call `fn` with argc LatValues; write the result into *out.
 * Returns 0 on success. On failure returns non-zero, sets out->tag = LAT_ERR,
 * and writes a NUL-terminated message to err (truncated to errcap).
 * HOT path — no Foundation; the only heap traffic beyond the interpreter's own
 * is the single result buffer of a LAT_BUF result (see OWNERSHIP).
 *
 * OWNERSHIP of LAT_BUF / LAT_STR buffers:
 *   • ARGUMENT buffers (argv[k].buf, tag LAT_BUF) are owned by the CALLER. They
 *     need only stay valid for the duration of this call; Lattice copies what
 *     it decodes. The caller frees them (they are typically caller-side scratch,
 *     e.g. a std::vector<uint8_t>). Do NOT pass them to lattice_buf_free.
 *   • A RESULT buffer (out->buf when out->tag == LAT_BUF or LAT_STR) is owned by
 *     LATTICE: it is freshly allocated here. The caller MUST hand it to
 *     lattice_buf_free exactly once after decoding it. On any error path
 *     out->tag is LAT_ERR (or a scalar) and out->buf is left NULL — nothing to
 *     free. */
int32_t lattice_call(void *handle, const char *fn,
                     const LatValue *argv, int32_t argc,
                     LatValue *out, char *err, int32_t errcap);

/* Advance the whole §6/§7 SYSTEM schedule by ONE clock step of `dt` seconds over
 * a seed `world` — the sim-tick surface (where lattice_call is the ported-
 * FUNCTION surface). `world` is a CompositeCodec DICT buffer of dotted resource
 * (`terrain.height`, `signal.rang`) → value; `worldlen` is its byte count.
 * Returns 0 with *out a LAT_BUF holding the resulting world DICT.
 *
 * The returned world carries, under reserved keys the host persists verbatim so
 * a save/restore replays bit-identically (spec §7 / the appendix wire form):
 *   • time.elapsed  (f) — the monotone injected clock (prior + dt)
 *   • time.dt       (f) — this step's dt
 *   • <System>.__time   — each TIMED system's serializable continuation record
 * plus every system's declared writes and the seeded reads that passed through.
 * A host applies DECLARED writes back and persists the reserved keys; it does
 * NOT blind-copy the world (declared-access-only — see lattice_systems).
 *
 * Determinism: this is the SAME interpreter path `tick_systems` and lattice-cli
 * run, so an embedded tick is byte-for-byte a lattice-cli tick of the same
 * module + seed + dt. HOT path — no Foundation. On any error (a non-dict world,
 * a runtime fault) returns non-zero, *out.tag = LAT_ERR, out->buf NULL, and a
 * NUL-terminated message in err. OWNERSHIP: the `world` argument buffer is
 * CALLER-owned (read-only here); the *out result buffer is LATTICE-owned — hand
 * it to lattice_buf_free exactly once after decoding, exactly like lattice_call. */
int32_t lattice_tick(void *handle, const uint8_t *world, int64_t worldlen, double dt,
                     LatValue *out, char *err, int32_t errcap);

/* Report the compiled module's SYSTEM manifest so a host can seed and apply
 * honestly (declared access only). Returns 0 with *out a LAT_BUF holding an
 * ARRAY (declaration order) of one DICT per system, each with keys:
 *   • name   (str)          — the system's name
 *   • reads  (array of str) — its declared `reads:` resources, declaration order
 *   • writes (array of str) — its declared `writes:` resources, declaration order
 *   • timed  (bool)         — true when the step is a §7 timeline (so the host
 *                             knows to persist a `<name>.__time` continuation)
 * A host seeds ONLY the union of `reads` (from its world mirror) and applies
 * ONLY the union of `writes` back; the language already refuses (compile error)
 * a step that writes an undeclared resource, so the manifest is exhaustive.
 * COLD path (pure metadata, no interpreter run). OWNERSHIP: the *out result
 * buffer is LATTICE-owned — free it with lattice_buf_free once after decoding. */
int32_t lattice_systems(void *handle, LatValue *out, char *err, int32_t errcap);

/* ---------------------------------------------------------------------------
 * The PERSISTENT HELD WORLD — substrate ladder Rung 2 (docs/SUBSTRATE.md §2).
 * ---------------------------------------------------------------------------
 * Where lattice_tick is the COPY path (a fresh whole world in, the whole world
 * out — O(world size) of marshal per tick), the held-world surface keeps the
 * world INSIDE the VM across ticks and crosses only O(writes-changed):
 *
 *   w = lattice_world_create(handle, seed, seedlen, err, errcap);  // seed ONCE
 *   lattice_world_tick(w, reads, readslen, dt, &out, err, errcap); // per tick
 *   lattice_world_snapshot(w, &out, err, errcap);                  // save/reconcile
 *   lattice_world_destroy(w);
 *
 * ONE held world per module (the one-handle rule: a held world drives the
 * module's single, non-re-entrant interpreter — do NOT interleave lattice_tick
 * copy-path calls with a live held world on the SAME module handle). The world
 * handle retains the module handle, so it stays valid even if the caller frees
 * the module first; still, destroy the world before the module by convention.
 *
 * This is the Swift `HeldWorld` (Contour.swift) proven BIT-IDENTICAL to the copy
 * path (SubstrateHeldWorldTests): the held trajectory equals lattice_tick's step
 * for step, and the write-diff, applied to a host mirror, reconstructs the copy
 * path's whole world. The copy path stays the reversible floor and the ORACLE.
 */

/* Create a persistent held world over an already-compiled module. `seed` is a
 * CompositeCodec DICT buffer (dotted resource -> value) — seed EVERY declared
 * read the host will inject each tick with an initial value here, so per-tick
 * injection is a pure in-place update and the held trajectory stays byte-exact
 * (see lattice_world_tick). Returns an opaque world handle, or NULL on error
 * (a non-dict seed, a null module) with a NUL-terminated message in err. COLD —
 * once at load / on a save restore, never on the tick. */
void *lattice_world_create(void *handle, const uint8_t *seed, int64_t seedlen,
                           char *err, int32_t errcap);

/* Release a held world created by lattice_world_create. NULL is a no-op. */
void lattice_world_destroy(void *world);

/* Advance the held world ONE clock step of `dt` seconds IN PLACE, first merging
 * the partial `reads` DICT (a CompositeCodec buffer of the declared reads the
 * host computed FRESH this tick — a system's engine-bound inputs) onto the held
 * world. `reads` may be NULL / a zero-length / an empty dict for no injection.
 * Returns 0 with *out a LAT_BUF holding the WRITE-DIFF dict: every held-world
 * key whose value MOVED this tick (the declared writes, the reserved
 * time.elapsed/time.dt, and any advanced <System>.__time continuation), in
 * held-world key order — O(writes changed), NOT O(world). A read the host
 * injects that no system also writes never appears in the diff. Apply the diff's
 * declared writes back to the host store; the reserved keys ride in it too so a
 * save/restore replays bit-identically (spec §7).
 *
 * OWNERSHIP: the `reads` argument buffer is CALLER-owned (read-only here); the
 * *out result buffer is LATTICE-owned — hand it to lattice_buf_free exactly once
 * after decoding, exactly like lattice_tick. On any error (a non-dict reads
 * buffer, a runtime fault) returns non-zero, *out.tag = LAT_ERR, out->buf NULL,
 * a NUL-terminated message in err. HOT path — no Foundation. */
int32_t lattice_world_tick(void *world, const uint8_t *reads, int64_t readslen, double dt,
                           LatValue *out, char *err, int32_t errcap);

/* The current FULL held world as a LAT_BUF DICT — the snapshot surface (a host
 * save/reconcile, and the copy-path parity oracle). Returns 0 with *out a
 * LAT_BUF; the reserved clock and every continuation ride in it under their
 * reserved keys (the wire form a host persists). OWNERSHIP: the *out buffer is
 * LATTICE-owned — free it with lattice_buf_free once after decoding. A host that
 * restores this snapshot into a fresh held world (lattice_world_create with it
 * as the seed) resumes every suspended timeline bit-identically. */
int32_t lattice_world_snapshot(void *world, LatValue *out, char *err, int32_t errcap);

#ifdef __cplusplus
}
#endif

/* ===========================================================================
 * CompositeCodec — the LAT_BUF byte format (SINGLE SOURCE OF TRUTH)
 * ===========================================================================
 * A composite Value serializes to a self-describing little-endian byte stream.
 * It is the same canonical shape Plumb bit-certifies (Value.canonical), carried
 * as raw LE bytes instead of ASCII hex: every float is the 8-byte little-endian
 * IEEE-754 bit pattern (identical bytes to Value.hexLE decoded), dict/record
 * fields keep insertion order, a basis is its three COLUMNS (x,y,z axes). No
 * ASCII-hex, no Foundation, no ambiguity — so it is legal on the hot path where
 * Value.canonical's String(format:) is not. buflen bounds the top-level value;
 * str/array/dict/record carry their own inner counts.
 *
 * All multi-byte integers are LITTLE-ENDIAN. One value = 1 tag byte + payload:
 *
 *   0x00 INT     int64   : 8 bytes LE
 *   0x01 FLOAT   float64 : 8 bytes LE (IEEE-754 bit pattern)
 *   0x02 BOOL    bool    : 1 byte (0 | 1)
 *   0x03 STR     string  : u32 LE byteLen + that many UTF-8 bytes
 *   0x04 ARRAY   array   : u32 LE count + <count> values
 *   0x05 DICT    dict    : u32 LE count + <count> (key value) pairs, insertion order
 *   0x06 VEC2    vector2 : 2 float64 LE (each real_t/Float32 WIDENED to double)
 *   0x07 VEC3    vector3 : 3 float64 LE (widened)
 *   0x08 BASIS   basis   : 9 float64 LE (widened), COLUMN order x,y,z axes
 *   0x09 RECORD  record  : STR(name payload: u32 len + bytes) + u32 LE field count
 *                          + <count> (key value) pairs, insertion order
 *   0x0a NULL    null    : no payload
 *
 * Float32 boundary (preserved EXACTLY, mirroring the scalar ABI): a vec2/vec3/
 * basis component is real_t/Float32; the encoder WIDENS it to double before
 * writing the 8 LE bytes (what Value.canonical / a Variant `v.x` read does), and
 * the decoder NARROWS back to real_t when reconstructing the Vector/Basis (what
 * Vector3(double,…) / Basis(...) storage does). A plain FLOAT (a dict field like
 * "yaw", an array element) is a full double and crosses unchanged. This keeps a
 * dict/array carrying vectors bit-identical to GDScript by construction, exactly
 * as the scalar vec3 path already was.
 *
 * Both the encoder (Swift, LatticeEmbed.swift) and every decoder (the godot-cpp
 * host, contour_kernel.cpp) MUST read this table as the contract. */

#endif /* LATTICE_EMBED_H */
