# PLAN_PHYSICS — the feel of matter (sand & water realism)

*2026-07-07, from Nicco: "I want to continue working on physics. Sand
and water need more realism. I want waves." Companion to
`strata/docs/ONE_APP.md` (the tool/pipeline track — different repo,
different muscles, safe to interleave). The Grain + the Watershed.*

## Where physics stands (so we build on it, not beside it)

- **Sand (the Grain):** GPU heightfield sim, conserved volume,
  footstep ejecta/craters/bow waves, angle-of-repose avalanches, wet
  raises repose, wind erodes. 1024² at 2.3cm texels over 24m.
- **Water tier 1 (Hydrology):** hourly basin balance — storms swell
  rivers, droughts drop lakes. Sim-contract state.
- **Water tier 2 (WaterField):** 1024² pipe-model depth field at 2m
  texels, scrolling window — rain streams down real slopes, pools,
  drains. Presentation-only.
- **Water tier 2.5 (WaterWaves):** 512² damped wave-equation window at
  12.5cm — wading rings, rain pocks, wind chop, vertex displacement.
- **Shader:** screen-space refraction, depth absorption, posterized
  foam, golden-hour palette, flow-map advection on rivers.
- **The sea:** flat disc + tide (`TIDE_AMP` sine) + the wave window
  near the focus. **This is the gap the eye hits first — the ocean
  has ripples but no waves.**
- **Tier 3 (named in STATUS, unbuilt):** near-window sediment coupling
  — water moving sand.

## Laws (every phase obeys these)

1. **Presentation vs sim:** everything below is presentation-only —
   off headless, never saved, never fingerprinted — EXCEPT where a
   phase says it writes sim state, and then it rides the full sim
   contract (hour_tick, WorldState mirror, catch-up, soak).
2. **Determinism where it counts:** stateless functions of time/wind
   are free; anything stateful must replay.
3. **Budgets:** the existing sand-field budget is the bar; no new
   always-on cost beyond one field's worth without a knob.
4. **Probes headless-first** (Movie Maker + minimized only when a
   window is unavoidable). Every phase ships its probe + a Toolkit
   summary()/knob (systems the Toolkit can't see are debt).
5. **The look is gouache:** foam is painted and posterized, crests are
   the pool's pink language at golden hour. Realism in *behavior*,
   never photorealism in rendering.

## W-track — the water

**W1 · Ocean swell.** The sea surface gets real waves: a sum of
Gerstner/trochoidal components (or a small tiling FFT patch if Gerstner
bands read too regular) displacing the sea mesh + wave-window verts.
Amplitude/wavelength/direction driven by Weather — wind speed and
fetch; a storm sends heavy swell ahead of itself (fronts already travel
— swell is their herald, arriving before the rain does: free foreshadowing).
Stateless in time+wind ⇒ no sim contract, off headless.
✓ From the strand, the horizon visibly rolls; storm swell reads bigger
than calm; probe renders A/B calm/storm shots headless.

**✅ DONE 2026-07-07 (commit 49714dc, the Watershed/the Elements).**
`SeaSwell` autoload: stateless energy function of (time, wind, fronts)
— each traveling front radiates swell scaled by its kind's wind²,
e-folding **5200m ahead of its leading edge** (vs the 800m rain edge:
rollers arrive hours before the rain — the herald, built). 4 Gerstner
components in the water shader's vertex stage, sea meshes only
(`swell_boost`), crests join the posterized foam + water_gold; new
1600m mid-detail sea disc; far disc now follows the focus. Physics
untouched: `sea_surface()` stays flat+tide (buoyancy mismatch accepted
at W1). Toolkit `SWELL` line + `force_amp` knob; `tests/sea_probe.tscn`
(SEA_WX=calm|storm) — A/B verified by eye; scene test pins herald
monotonicity + storm>calm. Soak untouched (bit-identical on fixed
data). W2 note: `swell_dir` + per-component rotations are the
direction field shoaling/breakers need; bathymetry must reach the
fragment/vertex stage for depth attenuation.

**W2 · Shoaling + breakers.** Depth-aware modulation near shore using
the real bathymetry (Strata bakes it): waves slow and steepen as depth
shrinks, break past a steepness threshold, and the breaker line follows
the actual seabed — reefs and bars make real surf zones. Painted
posterized foam crests + afterfoam sheets. Direction = swell direction,
so the lee shore is calm (the island shelters itself — same law as the
rain shadow, felt in the water).
✓ Breakers form on the windward strand and not in the lee bay;
a shallow bar breaks offshore while deep coast doesn't.

**W3 · Swash + the wet strand.** Run-up: each breaker sends a foam
tongue up the beach slope and drags it back. The swash band WETS the
ground (feeds the existing `ground_wetness`/sand wet-repose locally) so
the strand darkens in a live band that follows the tide + swell.
Mostly stateless (band = f(tide, swell, slope)); the wetness deposit
rides Climate's existing field.
✓ The beach shows a dark wet band that breathes with the surf; sand
in the band holds steeper footprint walls (wet repose already exists).

**W4 · Sediment coupling — tier 3, the flagship.** In the sand-patch
window, water flux moves sand: bedload transport in the shared texels —
rain rivulets carve miniature channels in the sand patch, the swash
zone reworks and **erases footprints on the strand** (the tide heals
the beach), heavy flow scours around obstacles. Sand stays conserved;
water field supplies the flux. This is stateful only inside the
transient window (like the sand field today) — no save, no soak.
✓ Footprints below the swash line are gone after a few waves; a
rain-hour leaves visible rivulet fans on a dune slope; conservation
unit test still passes.

**W5 · Rivers that carry their water (fill-mode maturation).** Promote
the K-toggle findings: channel friction + pre-fill are already in;
decide the shipping hybrid — sim water in the near window, draped
ribbons at distance, one crossfade. Rapids foam ties into the same
crest language as W2.
✓ Standing in a river, the water around you is the sim (pushes, pools,
rises in storms); at 300m it's the ribbon; no visible seam at the swap.

## S-track — the sand

**S1 · Material response pass.** One tuning sweep with cards on the
table: ejecta shape per action (walk/run/land/slide), plow wave width
vs speed, crater rim falloff — judged against reference clips (Journey
is the bar). Pure constants, cheap, big feel payoff.

**S2 · Wind-driven surface life.** The wind already erodes; make it
*visible*: migrating ripple patterns keyed to `wind_strength` +
direction (shader-side phase drift on the existing ripple bands),
saltation streamers off dune crests in gales (particles exist —
gate + directionalize them).
✓ A gale hour visibly re-combs a dune face; streamers blow off crests.

**S3 · Mud (the wet-ground material).** Where ground wetness is high
and sand density low (wetland/oasis biomes), footsteps press DOWN and
hold (no ejecta, slow rebound) — the sand field's existing signed
volume with a different response curve + darker sheen. Rain turns
paths sticky; the Traces wear layer already knows where paths are.
✓ A stormy day makes the pond trail (new world's wetland) read
pressed and glossy; prints outlast sand prints by hours.

## Order

W1 → W2 are one arc (the ocean exists, then it meets the land) — do
them together, they're the "I want waves" ask. W3 → W4 are the second
arc (the water touches the world) — W4 is the demo moment. S1 anytime
(constants). S2/S3/W5 as mood strikes between pipeline phases.

## Open questions (kitchen table)

- Swell in the pink language: do crests go pink at golden hour like
  everything else, or does the OCEAN get its own palette moment?
- Boats someday? W2's breaker map is also the "where can you land a
  boat" map — worth keeping the data around.
- Does the tide range grow? Real tides + swash + wet band = a shore
  that's a different place at dawn than at noon (forage/creature hooks).
