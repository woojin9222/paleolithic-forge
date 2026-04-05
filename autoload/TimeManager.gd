extends Node

## Day/night cycle and season system

signal time_changed(hour: float)
signal day_changed(day: int)
signal season_changed(season: String)

# Time of day (0.0 ~ 24.0)
var current_hour: float = 8.0
var current_day: int = 1
var current_season_index: int = 0  # 0=Spring, 1=Summer, 2=Autumn, 3=Winter

# 1 real second = this many in-game minutes
const MINUTES_PER_SECOND := 1.0
const HOURS_PER_DAY := 24.0
const DAYS_PER_SEASON := 10

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]

# Temperature ranges per season [min_night, max_day]
const SEASON_TEMPS := {
	"Spring": { "night": 25.0, "day": 55.0 },
	"Summer": { "night": 45.0, "day": 75.0 },
	"Autumn": { "night": 20.0, "day": 45.0 },
	"Winter": { "night": 5.0, "day": 25.0 },
}

var paused: bool = false

func _process(delta: float) -> void:
	if paused:
		return

	var prev_hour := current_hour
	current_hour += (MINUTES_PER_SECOND * delta) / 60.0

	if current_hour >= HOURS_PER_DAY:
		current_hour -= HOURS_PER_DAY
		current_day += 1
		day_changed.emit(current_day)

		if (current_day - 1) % DAYS_PER_SEASON == 0:
			current_season_index = (current_season_index + 1) % 4
			season_changed.emit(get_season())

	time_changed.emit(current_hour)

func get_season() -> String:
	return SEASONS[current_season_index]

func is_daytime() -> bool:
	return current_hour >= 6.0 and current_hour < 20.0

func get_day_progress() -> float:
	# 0 at sunrise(6), 1 at sunset(20), for sun angle
	if current_hour < 6.0:
		return 0.0
	elif current_hour > 20.0:
		return 0.0
	return (current_hour - 6.0) / 14.0

func get_darkness() -> float:
	# 0 = full daylight, 1 = full night
	if current_hour >= 8.0 and current_hour <= 18.0:
		return 0.0
	elif current_hour >= 21.0 or current_hour <= 5.0:
		return 1.0
	elif current_hour < 8.0:
		return 1.0 - (current_hour - 5.0) / 3.0
	else:
		return (current_hour - 18.0) / 3.0

func get_ambient_temperature() -> float:
	var season_data: Dictionary = SEASON_TEMPS[get_season()]
	var night_temp: float = season_data["night"]
	var day_temp: float = season_data["day"]

	# Sinusoidal temperature curve, warmest at 14:00, coldest at 4:00
	var t := sin((current_hour - 4.0) / 24.0 * TAU) * 0.5 + 0.5
	return lerp(night_temp, day_temp, t)

func get_time_string() -> String:
	var h := int(current_hour)
	var m := int((current_hour - h) * 60)
	return "%02d:%02d" % [h, m]
