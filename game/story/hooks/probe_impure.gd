extends QuestHooks
## NEGATIVE FIXTURE (DESIGN_QUESTS §6, law 1) — an INTENTIONALLY IMPURE
## hook whose only purpose is to prove the harness makes a purity violation
## VISIBLE (the same discipline the linter self-probes carry: a guard that
## can't bite is worse than none). Never referenced by shipped content.
##
## The crime: it draws from the GLOBAL, UNSEEDED RNG (bare randf) instead of
## q.roll. That is exactly the kind of reach past (WorldState, Items, q) the
## laws forbid — and it breaks restore-then-replay bit-identity, which the
## harness's _purity_probe asserts by running it twice from an identical
## state and demanding the outputs DIFFER. (On the fork engine the
## determinism trap would also name a bare randf fired inside advance_hours;
## the probe drives this one via a plain key write, off the armed section,
## so it is portable to stock Godot too.)


func on_stage(q: QuestRun, _stage: String) -> void:
	# Fires on the probe quest's root latch (its only reached stage). No
	# stage-id literal here — the framework content-id fence forbids naming a
	# data record's id in framework source, and a shipped quest's stages are
	# such ids. IMPURITY, on purpose: unseeded global RNG — not replay-stable.
	var draws := PackedStringArray()
	for i in 4:
		draws.append(str(randf()))
	q.set_value("test.impure.draw", ", ".join(draws))
