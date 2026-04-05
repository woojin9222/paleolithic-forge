extends CharacterBody2D

## Player controller for isometric movement

signal started_gathering(resource_node: Node2D)
signal stopped_gathering()

@export var move_speed: float = 150.0
@export var sprint_multiplier: float = 1.6
@export var stamina_drain: float = 15.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var interact_area: Area2D = $InteractArea
@onready var camera: Camera2D = $Camera2D

var facing_dir: Vector2 = Vector2.DOWN
var is_gathering: bool = false
var gather_target: Node2D = null
var gather_timer: float = 0.0
const GATHER_TIME := 1.5

# Touch/mobile input
var touch_move_dir: Vector2 = Vector2.ZERO

func _ready() -> void:
	camera.make_current()

func _physics_process(delta: float) -> void:
	if not GameManager.is_alive:
		velocity = Vector2.ZERO
		return

	if is_gathering:
		_process_gathering(delta)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Input
	var input_dir := _get_input_direction()

	# Convert to isometric movement
	# In isometric: "up" on screen = (-1, -1) in world, etc.
	var iso_dir := Vector2.ZERO
	iso_dir.x = input_dir.x - input_dir.y
	iso_dir.y = (input_dir.x + input_dir.y) * 0.5

	if iso_dir.length() > 0:
		iso_dir = iso_dir.normalized()
		facing_dir = iso_dir

	# Sprint
	var speed := move_speed
	var sprinting := Input.is_action_pressed("sprint") and iso_dir.length() > 0
	if sprinting and GameManager.stamina > 0:
		speed *= sprint_multiplier
		GameManager.stamina = max(0.0, GameManager.stamina - stamina_drain * delta)
		GameManager.is_sprinting = true
	else:
		GameManager.is_sprinting = false

	velocity = iso_dir * speed
	move_and_slide()

	# Animation
	_update_animation(iso_dir)

func _get_input_direction() -> Vector2:
	# Keyboard
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1

	# Mobile joystick override
	if touch_move_dir.length() > 0.1:
		dir = touch_move_dir

	return dir.normalized() if dir.length() > 0 else dir

func _update_animation(move_dir: Vector2) -> void:
	if not anim_player:
		return
	if move_dir.length() < 0.01:
		anim_player.play("idle")
	else:
		anim_player.play("walk")

	# Flip sprite based on horizontal direction
	if move_dir.x < -0.1:
		sprite.flip_h = true
	elif move_dir.x > 0.1:
		sprite.flip_h = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
	if event.is_action_pressed("attack"):
		_try_attack()

func _try_interact() -> void:
	if is_gathering:
		_cancel_gathering()
		return

	# Find nearest interactable in range
	var bodies := interact_area.get_overlapping_bodies()
	var areas := interact_area.get_overlapping_areas()

	for body in bodies:
		if body.has_method("interact"):
			body.interact(self)
			return
	for area in areas:
		if area.has_method("interact"):
			area.interact(self)
			return

func _try_attack() -> void:
	if is_gathering:
		_cancel_gathering()

	# Attack in facing direction
	var attack_pos := global_position + facing_dir * 30.0
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = attack_pos
	query.collision_mask = 4  # enemies layer
	var results := space.intersect_point(query, 5)

	for result in results:
		var collider := result["collider"]
		if collider.has_method("take_damage"):
			var equipped_damage := _get_weapon_damage()
			collider.take_damage(equipped_damage, self)

func _get_weapon_damage() -> float:
	if GameManager.has_item("stone_spear"):
		return 25.0
	if GameManager.has_item("hand_axe"):
		return 18.0
	if GameManager.has_item("stone_axe"):
		return 15.0
	return 8.0  # fist

func start_gathering(target: Node2D) -> void:
	is_gathering = true
	gather_target = target
	gather_timer = 0.0
	started_gathering.emit(target)

func _process_gathering(delta: float) -> void:
	if not is_instance_valid(gather_target):
		_cancel_gathering()
		return

	gather_timer += delta
	if gather_timer >= GATHER_TIME:
		if gather_target.has_method("harvest"):
			gather_target.harvest(self)
		_cancel_gathering()

func _cancel_gathering() -> void:
	is_gathering = false
	gather_target = null
	gather_timer = 0.0
	stopped_gathering.emit()

func get_gather_progress() -> float:
	if not is_gathering:
		return 0.0
	return gather_timer / GATHER_TIME
