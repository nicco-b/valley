extends Node
## Global game clock. Autoloaded as GameClock — the single source of time.
## Everything time-driven (sun, sky, schedules, ambiance) reads from here.
##
## Time is 1:1 with the real world (DECISIONS 2026-07-02, the ambient
## machine): a game day lasts a real day, and a new world's clock starts at
## the player's real local time, so the valley's sunset is your sunset.
## The clock is driven by wall-clock deltas, not frame deltas, so fps
## throttling and App Nap can't drift it. Skipped stretches — laptop
## sleep, app closed (via SaveGame) — are replayed through advance_hours(),
## which steps the whole simulation in hour chunks, never one giant leap.
##
## Seasons and daylight follow the real calendar and the player's real
## location (Settings.latitude/longitude): solar declination gives daylight
## length and hemisphere, the equation of time + longitude place solar noon
## in civil time. Sun-following systems read solar_hours(), never raw hours.

## Real minutes per full in-game day. 1440 = 1:1 with the real world.
@export var day_length_minutes := 1440.0

## Time of day in hours, [0, 24). Anchored to real local time for new
## worlds; only Stillness bends it away from your wall clock after that.
var hours := 9.0

## Days elapsed since the world began. Mirrored to WorldState "time.day".
var day := 0

## Time flows faster while deep sitters sit (Stillness skill). A live-play
## effect only — catch-up after sleep/close always runs 1:1.
var time_scale := 1.0

## winter | spring | summer | autumn — from the real date, hemisphere from
## the real latitude; mirrored to WorldState "time.season".
var season := ""

## Tick bus: simulation systems subscribe at the rate they need.
signal hour_tick(hour: int)

## Wall-clock gaps beyond this many seconds (laptop sleep, suspend, a long
## pause) are replayed as chunked catch-up instead of one smooth delta.
const GAP_SECONDS := 10.0

const SOLAR_ALTITUDE := -0.83  # degrees: sun-disc radius + refraction at rise/set
const AXIAL_TILT := 23.44
const SYNODIC_DAYS := 29.530588853  # real lunar month
const NEW_MOON_EPOCH := 947182440.0  # 2000-01-06 18:14 UTC, a known new moon

var _last_hour := -1
var _last_unix := 0.0
var _daylight := Vector2(6.0, 18.0)  # today's (sunrise, sunset), civil game-hours


func _ready() -> void:
	hours = civil_now()  # new world: the valley wakes at your local time
	refresh_daylight()   # (Settings loads after us and pokes this again)


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
## sleep, dev time travel). Each chunk moves the clock (hour_tick fires:
## weather rolls transitions, NPCs snapshot state) and then steps every
## member of the "sim_advance" group, so agents live the skipped hours
## instead of waking up stale.
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
		refresh_daylight()


## The real local civil time as fractional hours.
func civil_now() -> float:
	var t := Time.get_time_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0 + float(t.second) / 3600.0


## Today's (sunrise, sunset) in civil game-hours, from the real date and
## the player's real location.
func daylight_span() -> Vector2:
	return _daylight


## Hour-of-day warped into canonical solar space — sunrise maps to 6:00,
## noon to 12:00, sunset to 18:00 — so sun-following systems (sun arc,
## sky palette, dusk creatures) stay season-agnostic: they read solar
## hours and inherit real local daylight for free.
func solar_hours() -> float:
	var dl := _daylight.y - _daylight.x
	var since_rise := fposmod(hours - _daylight.x, 24.0)
	var p: float  # sun progress: 0 sunrise, 0.25 noon, 0.5 sunset, then night
	if since_rise < dl:
		p = 0.5 * since_rise / dl
	else:
		p = 0.5 + 0.5 * (since_rise - dl) / (24.0 - dl)
	return fmod(6.0 + p * 24.0, 24.0)


static func day_of_year(date: Dictionary) -> int:
	const DAYS_BEFORE_MONTH := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	var doy: int = DAYS_BEFORE_MONTH[int(date.month) - 1] + int(date.day)
	if int(date.month) > 2 and int(date.year) % 4 == 0:
		doy += 1
	return doy


## Astronomical-ish boundaries: Mar 20 / Jun 21 / Sep 22 / Dec 21,
## mirrored for the southern hemisphere.
static func season_for(date: Dictionary, southern := false) -> String:
	var md: int = int(date.month) * 100 + int(date.day)
	var s := "winter"
	if md >= 320 and md < 621:
		s = "spring"
	elif md >= 621 and md < 922:
		s = "summer"
	elif md >= 922 and md < 1221:
		s = "autumn"
	if southern:
		s = {"winter": "summer", "spring": "autumn", "summer": "winter", "autumn": "spring"}[s]
	return s


## Solar declination (radians) for a day of the year.
static func declination(doy: int) -> float:
	return deg_to_rad(-AXIAL_TILT) * cos(TAU * float(doy + 10) / 365.25)


## Daylight length in hours — the sunrise equation at a real latitude.
## Clamped short of polar day/night so the sun always rises and sets.
static func daylight_hours_for(doy: int, latitude_deg: float) -> float:
	var lat := deg_to_rad(latitude_deg)
	var decl := declination(doy)
	var cos_h := (sin(deg_to_rad(SOLAR_ALTITUDE)) - sin(lat) * sin(decl)) \
			/ (cos(lat) * cos(decl))
	var h := acos(clampf(cos_h, -1.0, 1.0))
	return clampf(2.0 * h / TAU * 24.0, 0.5, 23.5)


## Equation of time in hours (sundial minus clock), standard approximation.
static func equation_of_time(doy: int) -> float:
	var b := TAU * float(doy - 81) / 364.0
	return (9.87 * sin(2.0 * b) - 7.53 * cos(b) - 1.5 * sin(b)) / 60.0


## Recompute season and today's sunrise/sunset from the real date and the
## player's real location. Called hourly, at boot, and by Settings when the
## location resolves.
func refresh_daylight() -> void:
	var date := Time.get_date_dict_from_system()
	var doy := day_of_year(date)
	var lat := 45.0
	var lon := 0.0
	var settings := get_node_or_null("/root/Settings")  # loads after us at boot
	if settings:
		lat = settings.latitude
		lon = settings.longitude
	WorldState.set_value("sky.moon_phase", snappedf(moon_phase(), 0.01))
	var dl := daylight_hours_for(doy, lat)
	# Solar noon in civil time: timezone meridian vs. real longitude + EoT.
	var tz_hours: float = Time.get_time_zone_from_system().bias / 60.0
	var noon := 12.0 + tz_hours - lon / 15.0 - equation_of_time(doy)
	_daylight = Vector2(noon - dl * 0.5, noon + dl * 0.5)
	var s := season_for(date, lat < 0.0)
	if s == season:
		return
	var first := season == ""  # boot/new-session set, not a live turn
	season = s
	WorldState.set_value("time.season", s)
	if not first:
		print("[clock] season -> ", s)
		HUD.notify("the season turns — %s" % s)


## Real lunar phase at a unix time: 0 new, 0.5 full, wrapping at 1.
## Stateless in real time (kind-1: nothing to catch up).
static func moon_phase_at(unix: float) -> float:
	return fposmod((unix - NEW_MOON_EPOCH) / 86400.0, SYNODIC_DAYS) / SYNODIC_DAYS


func moon_phase() -> float:
	return moon_phase_at(Time.get_unix_time_from_system())


## Illuminated fraction of the moon, 0 (new) .. 1 (full) — how bright the
## night is. Dark-sky life (stars, glow-motes, fireflies) reads this.
## Placeholder: no moon disc in the sky yet — what the moon *is* belongs
## to the axioms conversation; this is the mechanical layer it will skin.
func moon_light() -> float:
	return 0.5 - 0.5 * cos(TAU * moon_phase())


func clock_text() -> String:
	return "%02d:%02d" % [int(hours) % 24, int(fmod(hours, 1.0) * 60.0)]


## --- Dev time travel (debug builds) --------------------------------------
## T: live forward to the next anchor (sunrise / noon / sunset / midnight).
## Shift+T: +1 day. Alt+T: +1 week. Shift+Alt+T: back to now (play mode).
## Forward travel always goes through advance_hours — the world lives the
## skipped time; there is no travelling back (the sim can't unlive hours).
## "Back to now" only re-anchors the dial to real local time: days lived
## during travel stay lived.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed("debug_time_skip"):
		var mods := event as InputEventWithModifiers
		var shift := mods != null and mods.shift_pressed
		var alt := mods != null and mods.alt_pressed
		if shift and alt:
			return_to_now()
		elif alt:
			_dev_skip(24.0 * 7.0, "a week passes")
		elif shift:
			_dev_skip(24.0, "a day passes")
		else:
			_dev_skip_to_anchor()


## Re-anchor the clock to real local time — the state normal play mode
## lives in. A dial move only, no simulation events.
func return_to_now() -> void:
	hours = civil_now()
	var msg := "back to now — %s, day %d (%s)" % [clock_text(), day, season]
	print("[clock] dev: ", msg)
	HUD.notify(msg)


func _dev_skip(dh: float, label: String) -> void:
	advance_hours(dh)
	var msg := "%s — %s, day %d (%s)" % [label, clock_text(), day, season]
	print("[clock] dev skip: ", msg)
	HUD.notify(msg)


func _dev_skip_to_anchor() -> void:
	var anchors := [
		[fposmod(_daylight.x, 24.0), "sunrise"],
		[fposmod((_daylight.x + _daylight.y) * 0.5, 24.0), "noon"],
		[fposmod(_daylight.y, 24.0), "sunset"],
		[0.0, "midnight"],
	]
	var best_d := 24.0
	var best_name := ""
	for a in anchors:
		var d := fposmod(a[0] - hours, 24.0)
		if d < 0.02:  # already standing on it: aim for its next occurrence
			d += 24.0
		if d < best_d:
			best_d = d
			best_name = a[1]
	_dev_skip(best_d, "→ %s" % best_name)
