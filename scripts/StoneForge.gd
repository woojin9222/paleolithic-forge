extends Control

## Stone Forge mini-game — tool crafting through timed strikes

signal forge_complete(quality: int)
signal forge_cancelled()

const TOTAL_STRIKES := 5
const GAUGE_FILL_TIME := 1.3  # seconds to fill gauge
const SWEET_ZONE_MIN := 0.28
const SWEET_ZONE_MAX := 0.70

var active: bool = false
var recipe_id: String = ""
var current_strike: int = 0
var quality: int = 100
var holding: bool = false
var hold_duration: float = 0.0
var zones: Array = []  # "pending", "hit", "miss"
var game_over: bool = false

@onready var gauge_bar: ProgressBar = $Panel/VBox/GaugeBar
@onready var gauge_label: Label = $Panel/VBox/GaugeLabel
@onready var quality_bar: ProgressBar = $Panel/VBox/QualityBar
@onready var quality_label: Label = $Panel/VBox/QualityLabel
@onready var zones_container: HBoxContainer = $Panel/VBox/ZonesContainer
@onready var hint_label: Label = $Panel/VBox/HintLabel
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_grade: Label = $ResultPanel/VBox/GradeLabel
@onready var result_desc: Label = $ResultPanel/VBox/DescLabel
@onready var restart_btn: Button = $ResultPanel/VBox/RestartBtn
@onready var panel: PanelContainer = $Panel

var zone_labels: Array = []

func _ready() -> void:
	visible = false
	result_panel.visible = false
	if restart_btn:
		restart_btn.pressed.connect(_on_close)

func open(target_recipe: String) -> void:
	recipe_id = target_recipe
	current_strike = 0
	quality = 100
	holding = false
	hold_duration = 0.0
	game_over = false
	zones.clear()
	for i in range(TOTAL_STRIKES):
		zones.append("pending")

	active = true
	visible = true
	result_panel.visible = false
	_update_ui()
	_build_zone_indicators()

func _process(delta: float) -> void:
	if not active or game_over:
		return

	if holding:
		hold_duration = min(hold_duration + delta / GAUGE_FILL_TIME, 1.0)
		_update_gauge()

func _unhandled_input(event: InputEvent) -> void:
	if not active or game_over:
		return

	# Mouse / touch hold
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_hold()
			else:
				_release_hold()

	if event is InputEventScreenTouch:
		if event.pressed:
			_start_hold()
		else:
			_release_hold()

func _start_hold() -> void:
	if holding or game_over:
		return
	holding = true
	hold_duration = 0.0

func _release_hold() -> void:
	if not holding:
		return
	holding = false

	var power := hold_duration
	_execute_strike(power)
	hold_duration = 0.0
	_update_gauge()

func _execute_strike(power: float) -> void:
	if current_strike >= TOTAL_STRIKES:
		return

	if power >= SWEET_ZONE_MIN and power <= SWEET_ZONE_MAX:
		zones[current_strike] = "hit"
	elif power < SWEET_ZONE_MIN:
		zones[current_strike] = "miss"
		quality = max(0, quality - 13)
	else:
		zones[current_strike] = "miss"
		quality = max(0, quality - 24)

	current_strike += 1
	_update_zone_indicators()
	_update_ui()

	if current_strike >= TOTAL_STRIKES:
		_finish_forge()

func _finish_forge() -> void:
	game_over = true

	var grade_data := _get_grade(quality)
	result_grade.text = grade_data["grade"]
	result_desc.text = grade_data["desc"]
	result_panel.visible = true
	hint_label.text = ""

	forge_complete.emit(quality)

func _on_close() -> void:
	active = false
	visible = false
	forge_cancelled.emit()

func _update_gauge() -> void:
	if gauge_bar:
		gauge_bar.value = hold_duration * 100.0

	if gauge_label:
		gauge_label.text = "Strike Force: %d%%" % int(hold_duration * 100)

	# Color feedback
	if gauge_bar:
		var sb := StyleBoxFlat.new()
		if hold_duration >= 0.72:
			sb.bg_color = Color(0.88, 0.19, 0.13)
		elif hold_duration >= SWEET_ZONE_MIN:
			sb.bg_color = Color(0.91, 0.45, 0.16)
		else:
			sb.bg_color = Color(0.3, 0.69, 0.31)
		gauge_bar.add_theme_stylebox_override("fill", sb)

func _update_ui() -> void:
	if quality_bar:
		quality_bar.value = quality
	if quality_label:
		quality_label.text = "Quality: %d%%" % quality
	if hint_label and not game_over:
		hint_label.text = "Hold & release to strike · Green zone = perfect blow"

func _build_zone_indicators() -> void:
	# Clear existing
	for child in zones_container.get_children():
		child.queue_free()
	zone_labels.clear()

	for i in range(TOTAL_STRIKES):
		var lbl := Label.new()
		lbl.text = ["I", "II", "III", "IV", "V"][i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(36, 36)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.48, 0.38))
		zones_container.add_child(lbl)
		zone_labels.append(lbl)

func _update_zone_indicators() -> void:
	for i in range(zones.size()):
		if i < zone_labels.size():
			match zones[i]:
				"hit":
					zone_labels[i].add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
				"miss":
					zone_labels[i].add_theme_color_override("font_color", Color(0.9, 0.2, 0.15))

func _get_grade(q: int) -> Dictionary:
	if q >= 90:
		return { "grade": "Masterwork", "desc": "A near-perfect tool — a flintknapper's finest hour." }
	if q >= 70:
		return { "grade": "Superior", "desc": "A keen, well-formed edge has emerged from the stone." }
	if q >= 50:
		return { "grade": "Serviceable", "desc": "Rough at the edges, but it will serve its purpose." }
	if q >= 30:
		return { "grade": "Crude", "desc": "Barely functional. The ancestors would not be impressed." }
	return { "grade": "Shattered", "desc": "The stone fractured. Nothing salvageable remains." }
