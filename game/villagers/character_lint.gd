class_name CharacterLint
## The cast sheet's linter (CREATION_KIT_REVIEW_V2 #3) — the character-record
## truths checked at commit time in test.sh (tests/character_lint.tscn), not
## discovered in the field. The quest_lint sibling for data/characters: static
## and side-effect free, lint_all() returns problems ([] = clean).
##
## Rules carried:
##   shape    the field schema (VillagerManager.SCHEMA) then the semantic
##            validator (VillagerManager.validate_character) — identity/body/
##            home/schedule/mind well formed, `kind` enumerated (villager|
##            creature), the schedule sound (id + satisfies), every place
##            ({x,z}/{marker}/"roam") well-shaped. This is the SAME judgement
##            `records validate characters` and spawn_character answer, so a
##            record the lint passes is one the game (and the desk) accept.
##   card     every `body.card` names a model card that EXISTS (the Cards
##            registry, scanned from assets/**/*.card.json): a placeholder with
##            no real art still has a `.card.json`. A dangling card would embody
##            into nothing. (Cards live in content, excluded from the framework
##            manifest — so a scaffolded game with no cards has nothing to
##            check; the harness SKIPs the card arm there, the tile/card SKIP
##            pattern.)
##   marker   marker references (a `home`, a schedule `at`) are well-SHAPED
##            non-empty ids — the checkable half of "resolvable". Their live
##            RESOLVABILITY is a runtime truth (a deleted marker falls back to
##            home BY DESIGN, never a lint failure), so shape is the honest
##            commit-time bar; it rides the `shape` arm (validate_character
##            owns the place grammar).

const DATA_DIR := "res://data/characters"


## Lint every character record in a directory (default data/characters).
## Content-empty (or an absent dir) lints clean — nothing to judge. Each
## problem is prefaced with the file it came from.
static func lint_all(dir_path := DATA_DIR) -> Array[String]:
	var problems: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return problems  # content-empty (or absent) — the honest floor
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var rec: Variant = Records.load_json(dir_path + "/" + f)
		if not (rec is Dictionary):
			problems.append("%s: not a JSON object" % f)
			continue
		for p in lint_record(rec):
			problems.append("%s: %s" % [f, p])
	return problems


## Lint one character record. Returns its problems ([] = clean). The shape
## arm runs first (the desk's own field-then-semantic door); a malformed
## record stops there — the deeper arms would only chase a shape the game
## already refuses.
static func lint_record(record: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	# shape: the exact judgement the records desk answers (field types, then
	# the semantic validator — kind, schedule, places, mind).
	var msg := Records.validate_message(record, VillagerManager.SCHEMA)
	if msg == "":
		msg = VillagerManager.validate_character(record)
	if msg != "":
		problems.append(msg)
		return problems
	# card: the model card must exist in the Cards registry (the content truth
	# the pure validator does not reach).
	var card := String(record.body.card)
	if not Cards.has(card):
		problems.append("model card '%s' does not exist (no such card slot)" % card)
	return problems
