extends CanvasLayer

## Main HUD — survival stats, time, inventory shortcut, mobile joystick

@onready var health_bar: ProgressBar = $HUDRoot/TopBar/HealthBar
@onready var hunger_bar: ProgressBar = $HUDRoot/TopBar/HungerBar
@onready var thirst_bar: ProgressBar = $HUDRoot/TopBar/ThirstBar
@onready var temp_bar: ProgressBar = $HUDRoot/TopBar/TempBar
@onready var stamina_bar: ProgressBar = $HUDRoot/TopBar/StaminaBar
@onready var time_label: Label = $HUDRoot/TopBar/TimeLabel
@onready var day_label: Label = $HUDRoot/TopBar/DayLabel
@onready var season_label: Label = $HUDRoot/TopBar/SeasonLabel
@onready var gather_bar: ProgressBar = $HUDRoot/GatherBar

# Mobile controls
@onready var joystick_area: Control = $HUDRoot/MobileControls/JoystickArea if has_node("HUDRoot/MobileControls/JoystickArea") else null
var joystick_active: bool = false
var joystick_center: Vector2 = Vector2.ZERO
var joystick_radius: float = 60.0
var player_ref: CharacterBody2D = null

func _ready() -> void:
	GameManager.stats_changed.connect(_on_stat_changed)
	TimeManager.time_changed.connect(_on_time_changed)
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.season_changed.connect(_on_season_changed)

	if gather_bar:
		gather_bar.visible = false

	_update_all_stats()
	_on_time_changed(TimeManager.current_hour)
	_on_day_changed(TimeManager.current_day)
	_on_season_changed(TimeManager.get_season())

	# Detect mobile
	_setup_mobile_controls()

func _process(_delta: float) -> void:
	_update_gather_progress()

func set_player(p: CharacterBody2D) -> void:
	player_ref = p

func _on_stat_changed(stat_name: String, value: float) -> void:
	match stat_name:
		"health":
			if health_bar: health_bar.value = value
		"hunger":
			if hunger_bar: hunger_bar.value = value
		"thirst":
			if thirst_bar: thirst_bar.value = value
		"temperature":
			if temp_bar: temp_bar.value = value
		"stamina":
			if stamina_bar: stamina_bar.value = value

func _update_all_stats() -> void:
	if health_bar: health_bar.value = GameManager.health
	if hunger_bar: hunger_bar.value = GameManager.hunger
	if thirst_bar: thirst_bar.value = GameManager.thirst
	if temp_bar: temp_bar.value = GameManager.temperature
	if stamina_bar: stamina_bar.value = GameManager.stamina

func _on_time_changed(_hour: float) -> void:
	if time_label:
		time_label.text = TimeManager.get_time_string()

func _on_day_changed(day: int) -> void:
	if day_label:
		day_label.text = "Day %d" % day

func _on_season_changed(season: String) -> void:
	if season_label:
		season_label.text = season

func _update_gather_progress() -> void:
	if not player_ref or not gather_bar:
		return
	var progress := player_ref.get_gather_progress()
	if progress > 0:
		gather_bar.visible = true
		gather_bar.value = progress * 100.0
	else:
		gather_bar.visible = false

func _setup_mobile_controls() -> void:
	# Simple touch detection - joystick will work on mobile
	if OS.has_feature("mobile") or OS.has_feature("web"):
		if joystick_area:
			joystick_area.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not player_ref:
		return

	# Virtual joystick for mobile
	if event is InputEventScreenTouch:
		if event.position.x < get_viewport().get_visible_rect().size.x * 0.4:
			if event.pressed:
				joystick_active = true
				joystick_center = event.position
			else:
				joystick_active = false
				player_ref.touch_move_dir = Vector2.ZERO

	if event is InputEventScreenDrag and joystick_active:
		var diff := event.position - joystick_center
		if diff.length() > 10:
			player_ref.touch_move_dir = diff.normalized()
		else:
			player_ref.touch_move_dir = Vector2.ZERO
