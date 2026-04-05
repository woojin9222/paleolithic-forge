extends Node

## Procedural event system — raids, weather, discoveries, visitors

signal event_started(event: Dictionary)
signal event_ended(event: Dictionary)
signal notification(message: String, severity: String)

# Severity: "info", "warning", "danger"

var active_events: Array = []
var event_cooldowns: Dictionary = {}
var _time_since_last_event: float = 0.0

# How often events can trigger (seconds)
const MIN_EVENT_INTERVAL := 60.0
const BASE_RAID_INTERVAL  := 300.0  # 5 min, decreases with threat level

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	TimeManager.day_changed.connect(_on_day_changed)

func _process(delta: float) -> void:
	_time_since_last_event += delta
	if _time_since_last_event >= MIN_EVENT_INTERVAL:
		_try_trigger_event()

func _try_trigger_event() -> void:
	var roll := _rng.randf()
	var threat := GameManager.threat_level

	# Raid probability scales with threat
	var raid_chance := 0.05 + threat * 0.04
	# Weather always possible
	var weather_chance := 0.15
	# Discovery when exploring (pawns are idle)
	var discovery_chance := 0.08
	# Visitor (friendly tribe)
	var visitor_chance := 0.06

	if roll < raid_chance:
		_trigger_raid()
	elif roll < raid_chance + weather_chance:
		_trigger_weather()
	elif roll < raid_chance + weather_chance + discovery_chance:
		_trigger_discovery()
	elif roll < raid_chance + weather_chance + discovery_chance + visitor_chance:
		_trigger_visitor()

	_time_since_last_event = 0.0

# ── Events ──

func _trigger_raid() -> void:
	var threat := GameManager.threat_level
	var count := 2 + threat  # number of raiders

	var event := {
		"type": "raid",
		"name": "Hostile Tribe Attack!",
		"description": "A hostile tribe approaches your camp. Arm your warriors!",
		"raider_count": count,
		"severity": "danger",
	}
	active_events.append(event)
	event_started.emit(event)
	notification.emit("⚠ Hostile tribe approaching! (%d raiders)" % count, "danger")
	GameManager.threat_level = min(5, GameManager.threat_level + 1)
	_spawn_raiders(count)

func _spawn_raiders(count: int) -> void:
	# Raiders spawn at map edge and move toward colony center
	var pawns := GameManager.pawns
	if pawns.is_empty():
		return
	var colony_center := Vector2.ZERO
	for p in pawns:
		colony_center += p.global_position
	colony_center /= pawns.size()

	# Spawn offset
	var spawn_dir := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	var spawn_origin := colony_center + spawn_dir * 600.0

	for i in range(count):
		var raider := _create_raider(spawn_origin + Vector2(i * 30.0, 0))
		get_tree().root.add_child(raider)

func _create_raider(pos: Vector2) -> Node2D:
	# Use Wildlife script but configured as hostile humanoid
	var raider := CharacterBody2D.new()
	raider.global_position = pos
	raider.add_to_group("raiders")
	raider.add_to_group("enemies")

	# Script behavior
	var script := GDScript.new()
	script.source_code = '''extends CharacterBody2D
var target = null
var health = 40.0
var speed = 70.0
var attack_timer = 0.0
func _ready():
	add_to_group("raiders")
func _physics_process(delta):
	if health <= 0: return
	var pawns = get_tree().get_nodes_in_group("pawns")
	if pawns.is_empty(): return
	target = pawns[0]
	for p in pawns:
		if global_position.distance_to(p.global_position) < global_position.distance_to(target.global_position):
			target = p
	var dist = global_position.distance_to(target.global_position)
	if dist > 25.0:
		velocity = (target.global_position - global_position).normalized() * speed
	else:
		velocity = Vector2.ZERO
		attack_timer += delta
		if attack_timer >= 1.5:
			attack_timer = 0.0
			if target.has_method("take_damage"):
				target.take_damage(8.0)
	move_and_slide()
func take_damage(amount, attacker=null):
	health -= amount
	if health <= 0:
		GameManager.add_resource("bone", 1)
		queue_free()
'''
	script.reload()
	raider.set_script(script)
	return raider

func _trigger_weather() -> void:
	var weathers := [
		{ "type": "storm", "name": "Thunderstorm", "desc": "A fierce storm hits. Seek shelter!", "temp_mod": -10.0, "severity": "warning" },
		{ "type": "heatwave", "name": "Heat Wave", "desc": "Scorching heat. Drink more water.", "temp_mod": +15.0, "severity": "warning" },
		{ "type": "cold_snap", "name": "Cold Snap", "desc": "Temperatures plummet overnight.", "temp_mod": -20.0, "severity": "warning" },
		{ "type": "fog", "name": "Dense Fog", "desc": "Visibility is low. Predators may be near.", "temp_mod": -5.0, "severity": "info" },
	]
	var w: Dictionary = weathers[_rng.randi() % weathers.size()]
	active_events.append(w)
	event_started.emit(w)
	notification.emit(w["name"] + ": " + w["desc"], w["severity"])
	# Auto-resolve after time
	await get_tree().create_timer(_rng.randf_range(60.0, 180.0)).timeout
	active_events.erase(w)
	event_ended.emit(w)

func _trigger_discovery() -> void:
	var discoveries := [
		{ "type": "flint_vein",  "name": "Flint Vein Found",  "desc": "Your tribe found a rich flint deposit nearby!",       "reward": {"flint": 8} },
		{ "type": "berry_patch", "name": "Berry Patch",        "desc": "A lush berry patch was discovered to the north.",     "reward": {"berry": 15} },
		{ "type": "cave",        "name": "Cave Discovered",    "desc": "A nearby cave offers shelter from the elements.",     "reward": {} },
		{ "type": "herb_cache",  "name": "Medicinal Herbs",    "desc": "Rare healing plants found near the river.",          "reward": {"plant_fiber": 10} },
		{ "type": "mammoth",     "name": "Mammoth Sighted",    "desc": "A mammoth roams the northern plains. Massive bounty if hunted.", "reward": {} },
	]
	var d: Dictionary = discoveries[_rng.randi() % discoveries.size()]
	for item: String in d.get("reward", {}):
		GameManager.add_resource(item, d["reward"][item])
	notification.emit(d["name"] + ": " + d["desc"], "info")

func _trigger_visitor() -> void:
	var visitors := [
		{ "name": "Wandering Hunter",  "desc": "A lone hunter seeks to join your tribe!",         "offers": {"raw_meat": 5} },
		{ "name": "Traveling Trader",  "desc": "A trader offers goods for stone and hide.",        "offers": {"berry": 10, "plant_fiber": 5} },
		{ "name": "Refugee Survivor",  "desc": "A survivor from a destroyed tribe wants shelter.", "offers": {} },
	]
	var v: Dictionary = visitors[_rng.randi() % visitors.size()]
	for item: String in v.get("offers", {}):
		GameManager.add_resource(item, v["offers"][item])
	notification.emit(v["name"] + ": " + v["desc"], "info")

func _on_day_changed(day: int) -> void:
	# Increase threat over time
	if day % 5 == 0:
		GameManager.threat_level = min(5, GameManager.threat_level + 1)
	notification.emit("Day %d begins. %s" % [day, TimeManager.get_season()], "info")

func get_active_weather() -> Dictionary:
	for event in active_events:
		if event.get("type") in ["storm", "heatwave", "cold_snap", "fog"]:
			return event
	return {}
