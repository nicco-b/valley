extends Node
## Global game clock. Autoloaded as GameClock — the single source of time.
## Everything time-driven (sun, sky, schedules, ambiance) reads from here.
##
## Time is 1:1 with the real world (DECISIONS 2026-07-02, the ambient
## machine): a game day lasts a real day. The clock is driven by wall-clock
## deltas, not frame deltas, so fps throttling and App Nap can't drift it.
## Skipped stretches — laptop sleep, app closed (via SaveGame) — are
## replayed through advance_hours(), which steps the whole simulation in
## hour chunks, never one giant leap.

## Real minutes per full in-game day. 1440 = 1:1 with the real world.
@export var day_length_minutes := 1440.0

## Time of day in hours, [0, 24).
var hours := 9.0

## Days elapsed since the world began. Mirrored to WorldState "time.day".
var day := 0

## Time flows faster while deep sitters sit (Stillness skill). A live-play
## effect only — catch-up after sleep/close always runs 1:1.
var time_scale := 1.0

## Tick bus: simulation systems subscribe at the rate they need.
signal hour_tick(hour: int)

## Wall-clock gaps beyond this many seconds (laptop sleep, suspend, a long
## pause) are replayed as chunked catch-up instead of one smooth delta.
const GAP_SECONDS := 10.0

## Seasons follow the real calendar (DECISIONS 2026-07-02): season and
## daylight length derive from the real system date. Northern-hemisphere
## arc — placeholder: hemisphere setting when Settings grows one.
## winter | spring | summer | autumn; mirrored to WorldState "time.season".
var season := ""

const DAYLIGHT_MEAN := 12.0
const DAYLIGHT_SWING := 3.5  # ± hours: ~8.5 at winter solstice, ~15.5 at summer
const DAYS_BEFORE_MONTH := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

var _last_hour := -1
var _last_unix := 0.0
var _daylight := Vector2(6.0, 18.0)  # today's (sunrise, sunset) in game-hours


func _ready() -> void:
	_update_season()


func _process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if _last_unix == 0.0:
		_last_unix = now
	var wall_delta := maxf(0.0, now - _last_unix)  # clock set backwards: hold
	_last_unix = now
	if wall_delta > GAP_SECONDS:
		advance_hours(wall_delta / 3600.0)  # 1:1 — the machine slept, the valley didn't
	else:
		_advance(hours_delta(wall_delta))


## Game-hours elapsed for a real-time delta — the conversion every
## continuous simulation uses.
func hours_delta(delta: float) -> float:
	return delta * time_scale * 24.0 / (day_length_minutes * 60.0)


## Advance the whole simulation by N game-hours in ≤1h chunks — the one
## shared path for every skipped stretch of time (load catch-up, laptop
## sleep, debug skip). Each chunk moves the clock (hour_tick fires: weather
## rolls transitions, NPCs snapshot state) and then steps every member of
## the "sim_advance" group, so agents live the skipped hours instead of
## waking up stale.
func advance_hours(total: float) -> void:
	while total > 0.0:
		var chunk := minf(total, 1.0)
		total -= chunk
		_advance(chunk)
		get_tree().call_group("sim_advance", "sim_advance_hours", chunk)


func _advance(dh: float) -> void:
	var advanced := hours + dh
	if advanced >= 24.0:
		day += 1
		WorldState.set_value("time.day", day)
	hours = fmod(advanced, 24.0)
	var h := int(hours)
	if h != _last_hour:
		_last_hour = h
		hour_tick.emit(h)
		_update_season()


## Today's (sunrise, sunset) in game-hours, from the real date.
func daylight_span() -> Vector2:
	return _daylight


## Hour-of-day warped into canonical solar space — sunrise maps to 6:00,
## noon to 12:00, sunset to 18:00 — so sun-following systems (sun arc,
## sky palette, dusk creatures) stay season-agnostic: they read solar
## hours and inherit real seasonal daylight for free.
func solar_hours() -> float:
	var p: float  # sun progress: 0 sunrise, 0.25 noon, 0.5 sunset, then night
	if hours >= _daylight.x and hours < _daylight.y:
		p = 0.5 * (hours - _daylight.x) / (_daylight.y - _daylight.x)
	else:
		var night := 24.0 - (_daylight.y - _daylight.x)
		p = 0.5 + 0.5 * fposmod(hours - _daylight.y, 24.0) / night
	return fmod(6.0 + p * 24.0, 24.0)


static func day_of_year(date: Dictionary) -> int:
	var doy: int = DAYS_BEFORE_MONTH[int(date.month) - 1] + int(date.day)
	if int(date.month) > 2 and int(date.year) % 4 == 0:
		doy += 1
	return doy


## Astronomical-ish boundaries: Mar 20 / Jun 21 / Sep 22 / Dec 21.
static func season_for(date: Dictionary) -> String:
	var md: int = int(date.month) * 100 + int(date.day)
	if md < 320:
		return "winter"
	if md < 621:
		return "spring"
	if md < 922:
		return "summer"
	if md < 1221:
		return "autumn"
	return "winter"


## Daylight length in hours for a day of the year (mood, not astronomy:
## a mid-latitude cosine, longest at the summer solstice).
static func daylight_hours_for(doy: int) -> float:
	return DAYLIGHT_MEAN - DAYLIGHT_SWING * cos(TAU * float(doy - 355) / 365.25)


func _update_season() -> void:
	var date := Time.get_date_dict_from_system()
	var dl := daylight_hours_for(day_of_year(date))
	_daylight = Vector2(12.0 - dl * 0.5, 12.0 + dl * 0.5)
	var s := season_for(date)
	if s == season:
		return
	var first := season == ""  # boot/new-session set, not a live turn
	season = s
	WorldState.set_value("time.season", s)
	if not first:
		print("[clock] season -> ", s)
		HUD.notify("the season turns — %s" % s)


func _unhandled_input(event: InputEvent) -> void:
	# Debug: skip forward one hour — through the shared path, so weather
	# and NPCs live the skipped hour instead of ignoring it.
	if event.is_action_pressed("debug_time_skip"):
		advance_hours(1.0)
