# PLAN_FRAMEWORK — the valley IS the engine

*2026-07-08, from Nicco: "i want the valleys current setup to basically
be the game engine that every game strata makes uses. valley should
probably be baked into our strata setup by now no? for example i dont
see any water in my new game. its blue surface color though."
Cross-repo: `strata/docs/ONE_APP.md` stays the law spine (games are
self-contained repos Strata opens; profiles-not-platforms; the fork
law; no Strata code ships in the game) — this plan is the valley-side
half of the template story. `strata/docs/PLAN_CREATION_LIBRARY.md` is
its structural sibling: the copy + provenance + offered-updates
pattern, generalized here from assets to code. Same laws, same voice
as PLAN_PHYSICS/PLAN_FABRIC.*

*2026-07-11, Nicco: this plan is TRANSITIONAL. It stands under
`strata/docs/PLAN_ENGINE.md` — valley hosts the framework only until
the Datum extraction ladder's rungs absorb it, rung by rung, not
forever. End state (PLAN_ENGINE E5): Plat is the editor, Datum is the
engine, and the Godot fork plus valley/native retire to museum
branches. Everything below is the interim shape, not the
destination.*

*2026-07-12, the move LANDED: the framework left home. Its source of
truth is now `~/code/datum/runtime` (the framework is named **datum**,
rev `94d618b2f467`), and the living plan moved with it —
**`datum/runtime/docs/PLAN_FRAMEWORK.md`** is the one that grows now.
Valley demoted to a pure game/content repo: `framework.json` and the
native SOURCE tree (`native/src`, the CMakeLists, `native/contour/src`
+ its build) are gone from here (preserved on `museum/native-pre-move`);
the kernel dylibs under `native/bin` + `native/contour/bin` stay,
because valley still BOOTS on them as consumer #1. Valley now pulls the
framework like any scaffolded game — `strata-cli framework update .`
(source→game) — and a hand-edit made here flows home with
`strata-cli framework push` (game→source). This file is a tombstone:
everything below the historical notes moved to datum. Read the datum
copy for the interim shape and the E5 destination.*

---

**This plan lives at `~/code/datum/runtime/docs/PLAN_FRAMEWORK.md`.**
The body that used to sit here (executive summary, the FW ladder, the
manifest law, the census) went with the framework when it moved out of
valley on 2026-07-12. Nothing framework-authoritative is maintained in
this repo anymore. The historical notes above stay as valley's own
record of why the engine once lived here.
