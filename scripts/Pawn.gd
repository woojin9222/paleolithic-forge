extends CharacterBody2D

class_name Pawn

## Tribe member — AI-driven colonist with needs, skills, and job execution

signal needs_changed(pawn: Pawn)
signal job_changed(pawn: Pawn, job: String)
signal pawn_died(pawn: Pawn)

# ── Identity ──
var pawn_name: String = ""
var is_selected: bool = false

# ── Needs (0~100) ──
var hunger: float = 80.0
var thirst: float = 80.0
var energy: float = 100.0
var health: float = 100.0
var mood: float = 70.0

const HUNGER_DRAIN  := 0.06  # per second
const THIRST_DRAIN  := 0.09
const ENERGY_DRAIN  := 0.03  # when working
const ENERGY_REGEN  := 0.08  # when resting (sleeping)
const MOOD_FLOOR    := 20.0  # mood below this causes work slowdown

# ── Skills (0~10) ──
var skills: Dictionary = {
	"gathering":    1,
	"hunting":      0,
	"crafting":     0,
	"construction": 0,
	"intelligence": 0,
	"cooking":      0,
	"medicine":     0,
}

# ── Traits ──
var traits: Array[String] = []
# e.g. "strong" (+melee), "quick" (+speed), "industrious" (+work speed)
# "greedy" (needs more food), "night_owl" (works at night)

# ── Job state ──
var current_job: String = "idle"
var current_job_data: Dictionary = {}
var job_target: Node2D = null
var job_timer: float = 0.0

# ── Movement ──
var move_speed: float = 80.0
var move_target: Vector2 = Vector2.ZERO
var is_moving: bool = false

# ── Equip ──
var equipped_tool: String = ""
var equipped_weapon: String = ""

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var selection_ring: Node2D = $SelectionRing
@onready var needs_bar: Control = $NeedsBar if has_node("NeedsBar") else null

var _job_tick: float = 0.0
const JOB_REASSIGN_INTERVAL := 2.0  # seconds between job checks

func _ready() -> void:
	add_to_group("pawns")
	add_to_group("player")  # so wildlife can find us
	if pawn_name == "":
		pawn_name = _random_name()
	if name_label:
		name_label.text = pawn_name
	if selection_ring:
		selection_ring.visible = false
	GameManager.register_pawn(self)

func _exit_tree() -> void:
	GameManager.unregister_pawn(self)

func _physics_process(delta: float) -> void:
	if health <= 0:
		return

	_update_needs(delta)
	_execute_movement(delta)
	_tick_job(delta)

func _update_needs(delta: float) -> void:
	hunger = max(0.0, hunger - HUNGER_DRAIN * delta)
	thirst = max(0.0, thirst - THIRST_DRAIN * delta)

	if current_job == JobSystem.JOB_REST:
		energy = min(100.0, energy + ENERGY_REGEN * delta)
	elif current_job != JobSystem.JOB_IDLE:
		energy = max(0.0, energy - ENERGY_DRAIN * delta)

	# Mood affected by needs
	var mood_target := 70.0
	if hunger < 30: mood_target -= 20.0
	if thirst < 30: mood_target -= 25.0
	if energy < 20: mood_target -= 15.0
	mood = lerp(mood, mood_target, delta * 0.1)

	# Damage from starvation/dehydration
	if hunger <= 0:
		health -= 0.3 * delta
	if thirst <= 0:
		health -= 0.5 * delta

	if health <= 0:
		_die()

	needs_changed.emit(self)

func _tick_job(delta: float) -> void:
	_job_tick += delta
	if _job_tick >= JOB_REASSIGN_INTERVAL and current_job == JobSystem.JOB_IDLE:
		_job_tick = 0.0
		_request_new_job()

	_process_current_job(delta)

func _request_new_job() -> void:
	var job := JobSystem.request_job(self)
	_assign_job(job)

func _assign_job(job: Dictionary) -> void:
	current_job = job["type"]
	current_job_data = job.get("data", {})
	job_target = job.get("target", null)
	job_timer = 0.0
	job_changed.emit(self, current_job)

	# Move toward target if it has a position
	if job_target and is_instance_valid(job_target):
		move_to(job_target.global_position)

func _process_current_job(delta: float) -> void:
	match current_job:
		JobSystem.JOB_IDLE:
			_do_wander(delta)

		JobSystem.JOB_EAT:
			_do_eat()

		JobSystem.JOB_REST:
			if energy >= 95.0:
				current_job = JobSystem.JOB_IDLE

		JobSystem.JOB_GATHER:
			_do_gather(delta)

		JobSystem.JOB_CHOP:
			_do_chop(delta)

		JobSystem.JOB_MINE:
			_do_mine(delta)

		JobSystem.JOB_HUNT:
			_do_hunt(delta)

		JobSystem.JOB_HAUL:
			_do_haul(delta)

		JobSystem.JOB_BUILD:
			_do_build(delta)

		JobSystem.JOB_CRAFT:
			_do_craft(delta)

		JobSystem.JOB_RESEARCH:
			pass  # research is passive — just assigned

func _do_wander(delta: float) -> void:
	if not is_moving:
		if randf() < 0.01:  # occasionally wander
			var wander_offset := Vector2(randf_range(-80, 80), randf_range(-80, 80))
			move_to(global_position + wander_offset)

func _do_eat() -> void:
	var food_id: String = current_job_data.get("food", "")
	if GameManager.remove_resource(food_id, 1):
		var food_data := GameManager.ITEMS_DB.get(food_id, {})
		hunger = min(100.0, hunger + food_data.get("nutrition", 10))
		thirst = min(100.0, thirst + 5.0)  # small thirst from food
	current_job = JobSystem.JOB_IDLE

func _do_gather(delta: float) -> void:
	if not is_instance_valid(job_target):
		current_job = JobSystem.JOB_IDLE
		return
	var dist := global_position.distance_to(job_target.global_position)
	if dist > 20.0:
		move_to(job_target.global_position)
		return
	is_moving = false
	job_timer += delta * _get_work_speed()
	if job_timer >= 2.0:
		if job_target.has_method("harvest"):
			job_target.harvest(self)
		current_job = JobSystem.JOB_IDLE
		_skill_gain("gathering")

func _do_chop(delta: float) -> void:
	_do_generic_work(delta, 3.0, "wood", 2, "gathering")

func _do_mine(delta: float) -> void:
	_do_generic_work(delta, 4.0, "stone", 2, "gathering")

func _do_generic_work(delta: float, time: float, res: String, amount: int, skill: String) -> void:
	if not is_instance_valid(job_target):
		current_job = JobSystem.JOB_IDLE
		return
	var dist := global_position.distance_to(job_target.global_position)
	if dist > 20.0:
		move_to(job_target.global_position)
		return
	is_moving = false
	job_timer += delta * _get_work_speed()
	if job_timer >= time:
		GameManager.add_resource(res, amount)
		if job_target.has_method("harvest"):
			job_target.harvest(self)
		current_job = JobSystem.JOB_IDLE
		_skill_gain(skill)

func _do_hunt(delta: float) -> void:
	if not is_instance_valid(job_target):
		current_job = JobSystem.JOB_IDLE
		return
	var dist := global_position.distance_to(job_target.global_position)
	if dist > 30.0:
		move_to(job_target.global_position)
		return
	# Attack
	job_timer += delta
	if job_timer >= 1.2:
		job_timer = 0.0
		var dmg := 15.0 + skills.get("hunting", 0) * 3.0
		if equipped_weapon == "stone_spear":
			dmg = 22.0
		elif equipped_weapon == "bow":
			dmg = 20.0
		if job_target.has_method("take_damage"):
			job_target.take_damage(dmg, self)
		_skill_gain("hunting")
	if not is_instance_valid(job_target):
		current_job = JobSystem.JOB_IDLE

func _do_haul(delta: float) -> void:
	var item: String = current_job_data.get("item", "")
	var amount: int = current_job_data.get("amount", 1)
	var from_pos: Vector2 = current_job_data.get("from", global_position)
	if global_position.distance_to(from_pos) > 20.0:
		move_to(from_pos)
		return
	# Picked up — add to stockpile
	GameManager.add_resource(item, amount)
	current_job = JobSystem.JOB_IDLE

func _do_build(delta: float) -> void:
	var tile_pos: Vector2i = current_job_data.get("tile", Vector2i.ZERO)
	var build_target_pos := WorldGenerator.tile_to_screen(tile_pos)
	if global_position.distance_to(build_target_pos) > 30.0:
		move_to(build_target_pos)
		return
	job_timer += delta * _get_work_speed()
	var build_time: float = current_job_data.get("build_time", 5.0)
	if job_timer >= build_time:
		# Signal build completion to BuildingSystem
		get_tree().call_group("building_system", "complete_build", current_job_data)
		current_job = JobSystem.JOB_IDLE
		_skill_gain("construction")

func _do_craft(delta: float) -> void:
	var recipe_id: String = current_job_data.get("recipe", "")
	job_timer += delta * _get_work_speed()
	var r := GameManager.RECIPES.get(recipe_id, {})
	if r.get("forge", false):
		# Trigger forge mini-game
		get_tree().call_group("forge_ui", "open", recipe_id)
		current_job = JobSystem.JOB_IDLE
		return
	var craft_time := 3.0
	if job_timer >= craft_time:
		GameManager.craft(recipe_id)
		current_job = JobSystem.JOB_IDLE
		_skill_gain("crafting")

func _execute_movement(delta: float) -> void:
	if not is_moving:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var dir := (move_target - global_position)
	if dir.length() < 5.0:
		is_moving = false
		velocity = Vector2.ZERO
	else:
		var spd := move_speed * (1.0 + traits.count("quick") * 0.2)
		velocity = dir.normalized() * spd
	move_and_slide()
	# Flip sprite
	if sprite and velocity.x < -5:
		sprite.flip_h = true
	elif sprite and velocity.x > 5:
		sprite.flip_h = false

func move_to(pos: Vector2) -> void:
	move_target = pos
	is_moving = true

func _get_work_speed() -> float:
	var spd := 1.0
	spd += traits.count("industrious") * 0.3
	spd += skills.get("crafting", 0) * 0.05
	if mood < MOOD_FLOOR:
		spd *= 0.6
	if energy < 30:
		spd *= 0.7
	return spd

func _skill_gain(skill_name: String) -> void:
	if not skills.has(skill_name):
		return
	# XP gain with diminishing returns
	var current_lvl: int = skills[skill_name]
	if current_lvl >= 10:
		return
	var xp_needed := (current_lvl + 1) * 200
	var xp_key := skill_name + "_xp"
	current_job_data[xp_key] = current_job_data.get(xp_key, 0) + randf_range(5, 15)
	if current_job_data.get(xp_key, 0) >= xp_needed:
		skills[skill_name] = current_lvl + 1
		current_job_data[xp_key] = 0.0

func take_damage(amount: float, _attacker = null) -> void:
	health -= amount
	if health <= 0:
		_die()

func heal(amount: float) -> void:
	health = min(100.0, health + amount)

func set_selected(sel: bool) -> void:
	is_selected = sel
	if selection_ring:
		selection_ring.visible = sel

func _die() -> void:
	health = 0.0
	pawn_died.emit(self)
	GameManager.unregister_pawn(self)
	# Drop items
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 2.0)
	tween.tween_callback(queue_free)

func _random_name() -> String:
	var names := ["Grak", "Ura", "Thorn", "Mira", "Bolg", "Sela", "Dug", "Fara",
				  "Rok", "Huna", "Krag", "Vela", "Odu", "Pira", "Brun", "Neka"]
	return names[randi() % names.size()]

func get_needs_summary() -> Dictionary:
	return {
		"hunger": hunger, "thirst": thirst,
		"energy": energy, "health": health, "mood": mood
	}
