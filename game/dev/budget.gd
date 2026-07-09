extends Node
## The world budget (autoload) — a METER, NOT A WALL. It reads the live world
## along the three axes the stress probe (tests/world_budget_probe.gd) charted
## — per-cell placement density, live agents, total placed records — and grades
## each green/amber/red against thresholds. NOTHING here writes sim state or
## refuses a placement: amber/red is INFORMATION. The Toolkit HUD wears a
## budget line, the `budget` link verb answers the same numbers, and Strata's
## inspector renders a Budget row from them.
##
## Thresholds are the FW4 record/fallback pattern: DEFAULTS below are the
## framework's measured-cliff defaults (honest margin under the knees); a game
## ships data/world/budget.json to tune them (per-axis, shallow-merged), and a
## content-empty game falls back to DEFAULTS. Framework file — its literals are
## thresholds (numbers) and axis keys, never a content id or an asset path.
##
## Live agents can't be counted generically (a mind is data, not a node), so
## the population is a REGISTRY like Records' reloaders: a sim that keeps agents
## registers a count Callable (WildlifeManager does); a content-empty game has
## no registrants and reads 0. The meter only ever CALLS these — it never
## advances or mutates a sim (soak stays bit-identical; verified against a
## same-tree baseline).
##
## Measured cliffs behind the defaults (fork engine, headless, 2026-07-09):
##   placement  cell (re)build hitch is linear ~0.02ms/instance for a typical
##              multi-node kit; crosses one 60fps frame (16.6ms) near 800/cell.
##              amber 250 (~5ms hitch) · red 600 (~12ms) — margin under the knee
##              for the GPU draw cost the headless probe can't see.
##   agents     advance_hours(12) catch-up ~40ms fixed + ~0.027ms/agent; the
##              catch-up doubles the fixed cost near ~1500 live agents (the
##              steady live frame stays flat). amber 500 · red 1200.
##   records    boot parse+validate ~2.5ms per 1000 rows (JSON-bound); 10k=26ms,
##              50k=126ms. amber 10000 · red 40000.

enum { GREEN, AMBER, RED }

const RECORD_PATH := "res://data/world/budget.json"

const DEFAULTS := {
	"cell_placements": {"amber": 250, "red": 600},
	"agents": {"amber": 500, "red": 1200},
	"records": {"amber": 10000, "red": 40000},
	"per_placement_ms": 0.02,  # measured build-hitch cost per placed instance
}

## The live thresholds: DEFAULTS shallow-merged with the content record.
var thresholds: Dictionary = {}

## Population sources (the agent registry): each returns a live agent count.
var _pop_sources: Array[Callable] = []


func _ready() -> void:
	reload()
	# The records desk (Strata R5) can re-read a tuned budget live, same door a
	# restart would take: `records reload world` re-loads data/world/*.
	Records.register_reloader("world", reload)


## (Re)load the thresholds: framework DEFAULTS under the content record.
func reload() -> void:
	thresholds = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(RECORD_PATH):
		return
	var parsed: Variant = Records.load_json(RECORD_PATH)
	if not (parsed is Dictionary):
		return
	for axis: String in parsed:
		if thresholds.has(axis) and thresholds[axis] is Dictionary \
				and parsed[axis] is Dictionary:
			for k: String in parsed[axis]:
				thresholds[axis][k] = parsed[axis][k]
		else:
			thresholds[axis] = parsed[axis]


## A sim registers a live agent-count source (framework registry, content
## fills it — WildlifeManager does in its _ready). Read-only: the meter only
## ever calls these.
func register_population(source: Callable) -> void:
	if not _pop_sources.has(source):
		_pop_sources.append(source)


# --- the three live readings ------------------------------------------------

## Where the world is being looked at (Toolkit fly cam, else player, else
## origin) — the cell the placement meter grades.
func focus_position() -> Vector3:
	if Toolkit.active and Toolkit.has_camera():
		return Toolkit.cam_position()
	var player: Node3D = get_tree().get_first_node_in_group("player")
	return player.global_position if player else Vector3.ZERO


func focus_cell() -> Vector2i:
	return CellRecords.cell_of(focus_position())


## Records placed in the focus cell (the one the hand can crowd).
func cell_count() -> int:
	return CellRecords.records(focus_cell()).size()


## Every placed record across the whole Chronicle (the boot-load axis).
func total_records() -> int:
	var n := 0
	for cell: Vector2i in CellRecords.all_cells():
		n += CellRecords.records(cell).size()
	return n


## Live agents, summed over the registered population sources (0 content-empty).
func agent_count() -> int:
	var n := 0
	for source: Callable in _pop_sources:
		if source.is_valid():
			n += int(source.call())
	return n


# --- grading ----------------------------------------------------------------

func grade(value: int, axis: String) -> int:
	var t: Dictionary = thresholds.get(axis, {})
	if value >= int(t.get("red", 1 << 30)):
		return RED
	if value >= int(t.get("amber", 1 << 30)):
		return AMBER
	return GREEN


func status_word(g: int) -> String:
	return ["green", "amber", "red"][g]


func status_color(g: int) -> Color:
	return [Color(0.55, 0.9, 0.5), Color(1.0, 0.78, 0.25), Color(1.0, 0.45, 0.4)][g]


## The worst grade across all three axes — the colour the HUD line wears.
func worst_grade() -> int:
	var c := cell_count()
	var a := agent_count()
	var r := total_records()
	return maxi(maxi(grade(c, "cell_placements"), grade(a, "agents")),
		grade(r, "records"))


## Every axis in one snapshot: value, thresholds, grade — the one truth the
## HUD line, the link verb, and Strata's Budget row all render.
func snapshot() -> Dictionary:
	var c := cell_count()
	var a := agent_count()
	var r := total_records()
	return {
		"cell": {"value": c, "grade": grade(c, "cell_placements"),
			"amber": int(thresholds.cell_placements.amber),
			"red": int(thresholds.cell_placements.red),
			"est_ms": c * float(thresholds.get("per_placement_ms", 0.02))},
		"agents": {"value": a, "grade": grade(a, "agents"),
			"amber": int(thresholds.agents.amber), "red": int(thresholds.agents.red)},
		"records": {"value": r, "grade": grade(r, "records"),
			"amber": int(thresholds.records.amber), "red": int(thresholds.records.red)},
	}


# --- renderings -------------------------------------------------------------

## The compact HUD line (this cell first, then the world). Wears no colour of
## its own — the Toolkit paints it by worst_grade().
func hud_line() -> String:
	var s := snapshot()
	return "BUDGET  cell %d/%d (~%.1fms)  ·  agents %d/%d  ·  records %d/%d" % [
		int(s.cell.value), int(s.cell.red), float(s.cell.est_ms),
		int(s.agents.value), int(s.agents.red),
		int(s.records.value), int(s.records.red)]


## The machine line for the `budget` link verb — Strata's BudgetReport parser
## pins this grammar (change both or neither). One token per axis:
## <axis>=<value>/<amber>/<red>:<grade>, plus the est build-hitch ms.
func link_line() -> String:
	var s := snapshot()
	return "ok budget cell=%d/%d/%d:%s agents=%d/%d/%d:%s records=%d/%d/%d:%s est_ms=%.1f" % [
		int(s.cell.value), int(s.cell.amber), int(s.cell.red), status_word(int(s.cell.grade)),
		int(s.agents.value), int(s.agents.amber), int(s.agents.red), status_word(int(s.agents.grade)),
		int(s.records.value), int(s.records.amber), int(s.records.red), status_word(int(s.records.grade)),
		float(s.cell.est_ms)]


## Toolkit world-panel line (the O overlay / `panel` verb read this).
func summary() -> String:
	var s := snapshot()
	return "cell %d (%s)  agents %d (%s)  records %d (%s)" % [
		int(s.cell.value), status_word(int(s.cell.grade)),
		int(s.agents.value), status_word(int(s.agents.grade)),
		int(s.records.value), status_word(int(s.records.grade))]
