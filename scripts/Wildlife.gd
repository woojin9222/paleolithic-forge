extends CharacterBody2D

## Base wildlife AI — herbivores and predators

class_name Wildlife

enum AnimalType { RABBIT, DEER, WOLF, BOAR, SABERTOOTH }
enum State { IDLE, WANDER, FLEE, CHASE, ATTACK, DEAD }

@export var animal_type: AnimalType = AnimalType.RABBIT
@export var max_health: float = 30.0
@export var move_speed: float = 80.0
@export var detection_range: float = 150.0
@export var attack_range: float = 25.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.2
@export var is_predator: bool = false

var health: float
var state: State = State.IDLE
var target: Node2D = null
var wander_dir: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0
var idle_timer: float = 0.0
var attack_timer: float = 0.0

# Loot drops
var loot_table: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null

func _ready() -> void:
	health = max_health
	_setup_animal()
	add_to_group("wildlife")
	if is_predator:
		add_to_group("predators")
	else:
		add_to_group("prey")

func _setup_animal() -> void:
	match animal_type:
		AnimalType.RABBIT:
			max_health = 15.0
			move_speed = 120.0
			detection_range = 100.0
			is_predator = false
			loot_table = { "raw_meat": 1, "hide": 1 }
		AnimalType.DEER:
			max_health = 40.0
			move_speed = 100.0
			detection_range = 140.0
			is_predator = false
			loot_table = { "raw_meat": 3, "hide": 2, "bone": 1 }
		AnimalType.WOLF:
			max_health = 60.0
			move_speed = 110.0
			detection_range = 180.0
			attack_damage = 12.0
			is_predator = true
			loot_table = { "raw_meat": 2, "hide": 2, "bone": 2 }
		AnimalType.BOAR:
			max_health = 80.0
			move_speed = 90.0
			detection_range = 100.0
			attack_damage = 18.0
			is_predator = false  # but fights back
			loot_table = { "raw_meat": 4, "hide": 3, "bone": 2 }
		AnimalType.SABERTOOTH:
			max_health = 150.0
			move_speed = 120.0
			detection_range = 220.0
			attack_damage = 30.0
			attack_cooldown = 1.5
			is_predator = true
			loot_table = { "raw_meat": 5, "hide": 4, "bone": 4 }
	health = max_health

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	_update_state(delta)
	_execute_state(delta)
	move_and_slide()

	# Flip sprite
	if velocity.x < -5:
		sprite.flip_h = true
	elif velocity.x > 5:
		sprite.flip_h = false

func _update_state(delta: float) -> void:
	var player := _find_player()
	if not player:
		if state == State.CHASE or state == State.ATTACK:
			state = State.WANDER
		return

	var dist := global_position.distance_to(player.global_position)

	match state:
		State.IDLE:
			idle_timer -= delta
			if idle_timer <= 0:
				state = State.WANDER
				wander_timer = randf_range(2.0, 5.0)
				wander_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

			if dist < detection_range:
				if is_predator:
					state = State.CHASE
					target = player
				else:
					state = State.FLEE
					target = player

		State.WANDER:
			wander_timer -= delta
			if wander_timer <= 0:
				state = State.IDLE
				idle_timer = randf_range(1.0, 3.0)

			if dist < detection_range:
				if is_predator:
					state = State.CHASE
					target = player
				else:
					state = State.FLEE
					target = player

		State.FLEE:
			if dist > detection_range * 1.8:
				state = State.WANDER
				target = null

		State.CHASE:
			if dist > detection_range * 2.5:
				state = State.WANDER
				target = null
			elif dist < attack_range:
				state = State.ATTACK

		State.ATTACK:
			if dist > attack_range * 1.5:
				state = State.CHASE

func _execute_state(delta: float) -> void:
	match state:
		State.IDLE:
			velocity = velocity.lerp(Vector2.ZERO, 5.0 * delta)

		State.WANDER:
			velocity = wander_dir * move_speed * 0.4

		State.FLEE:
			if target and is_instance_valid(target):
				var flee_dir := (global_position - target.global_position).normalized()
				velocity = flee_dir * move_speed * 1.3

		State.CHASE:
			if target and is_instance_valid(target):
				var chase_dir := (target.global_position - global_position).normalized()
				velocity = chase_dir * move_speed

		State.ATTACK:
			velocity = Vector2.ZERO
			attack_timer -= delta
			if attack_timer <= 0 and target and is_instance_valid(target):
				if target.global_position.distance_to(global_position) < attack_range:
					GameManager.take_damage(attack_damage)
					attack_timer = attack_cooldown

func take_damage(amount: float, attacker: Node2D) -> void:
	health -= amount
	if health <= 0:
		_die()
	elif not is_predator:
		# Boar fights back, others flee
		if animal_type == AnimalType.BOAR:
			state = State.CHASE
			is_predator = true  # temporary aggro
			target = attacker
		else:
			state = State.FLEE
			target = attacker
	else:
		target = attacker
		state = State.CHASE

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO

	# Drop loot
	for item_id: String in loot_table:
		GameManager.add_item(item_id, loot_table[item_id])

	# Fade out and remove
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 1.0)
	tween.tween_callback(queue_free)

func _find_player() -> CharacterBody2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as CharacterBody2D
	return null
