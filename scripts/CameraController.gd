extends Camera2D

## Free-roaming camera — pan, zoom, edge scroll (RimWorld-style)

@export var pan_speed: float = 400.0
@export var zoom_speed: float = 0.1
@export var zoom_min: float = 0.4
@export var zoom_max: float = 2.5
@export var edge_scroll_margin: float = 20.0
@export var edge_scroll_speed: float = 300.0

var is_panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var pan_origin: Vector2 = Vector2.ZERO

# Touch pinch-zoom
var touch_points: Dictionary = {}
var last_pinch_dist: float = 0.0

func _ready() -> void:
	make_current()
	zoom = Vector2(1.0, 1.0)

func _process(delta: float) -> void:
	_keyboard_pan(delta)
	_edge_scroll(delta)

func _unhandled_input(event: InputEvent) -> void:
	# ── Mouse wheel zoom ──
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_do_zoom(-zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_do_zoom(zoom_speed, event.position)
		# Middle-click pan
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_panning = true
				pan_start = event.position
				pan_origin = global_position
			else:
				is_panning = false

	if event is InputEventMouseMotion and is_panning:
		var delta_pan := (event.position - pan_start) / zoom
		global_position = pan_origin - delta_pan

	# ── Touch events ──
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
		else:
			touch_points.erase(event.index)
			last_pinch_dist = 0.0

	if event is InputEventScreenDrag:
		touch_points[event.index] = event.position

		if touch_points.size() == 1:
			# Single finger pan
			global_position -= event.relative / zoom

		elif touch_points.size() == 2:
			# Pinch zoom
			var pts := touch_points.values()
			var dist := pts[0].distance_to(pts[1])
			if last_pinch_dist > 0:
				var ratio := last_pinch_dist / dist
				var new_zoom := clamp(zoom.x * ratio, zoom_min, zoom_max)
				zoom = Vector2(new_zoom, new_zoom)
			last_pinch_dist = dist

func _keyboard_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	if dir.length() > 0:
		global_position += dir.normalized() * pan_speed * delta / zoom.x

func _edge_scroll(delta: float) -> void:
	if is_panning or touch_points.size() > 0:
		return
	var vp_size := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	var dir := Vector2.ZERO
	if mouse.x < edge_scroll_margin:            dir.x -= 1
	if mouse.x > vp_size.x - edge_scroll_margin: dir.x += 1
	if mouse.y < edge_scroll_margin:            dir.y -= 1
	if mouse.y > vp_size.y - edge_scroll_margin: dir.y += 1
	if dir.length() > 0:
		global_position += dir.normalized() * edge_scroll_speed * delta / zoom.x

func _do_zoom(delta_zoom: float, pivot: Vector2) -> void:
	var old_zoom := zoom.x
	var new_zoom := clamp(old_zoom + delta_zoom, zoom_min, zoom_max)
	zoom = Vector2(new_zoom, new_zoom)
	# Zoom toward mouse position
	var vp_center := get_viewport_rect().size / 2.0
	var offset := (pivot - vp_center) * (1.0 / old_zoom - 1.0 / new_zoom)
	global_position += offset

func center_on(world_pos: Vector2) -> void:
	global_position = world_pos
