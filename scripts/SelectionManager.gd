extends Node2D

## Handles pawn selection, right-click orders, drag-select box

signal selection_changed(selected_pawns: Array)
signal order_issued(order: Dictionary)

var selected_pawns: Array = []
var drag_selecting: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_rect: Rect2 = Rect2()

# Current interaction mode
enum Mode { SELECT, BUILD, DESIGNATE_GATHER, DESIGNATE_HUNT }
var current_mode: Mode = Mode.SELECT
var pending_build_id: String = ""

@onready var drag_box: ColorRect = $DragBox if has_node("DragBox") else null

func _ready() -> void:
	if drag_box:
		drag_box.visible = false
		drag_box.color = Color(0.3, 0.7, 1.0, 0.15)
		drag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_press(event.position)
		else:
			_on_left_release(event.position)

	if event is InputEventMouseMotion and drag_selecting:
		_update_drag(event.position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_on_right_click(event.position)

	# Cancel mode
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		current_mode = Mode.SELECT
		pending_build_id = ""

func _on_left_press(screen_pos: Vector2) -> void:
	match current_mode:
		Mode.SELECT:
			drag_selecting = true
			drag_start = screen_pos
			drag_rect = Rect2(screen_pos, Vector2.ZERO)

		Mode.BUILD:
			var world_pos := _screen_to_world(screen_pos)
			var tile_pos := WorldGenerator.screen_to_tile(world_pos)
			JobSystem.designate_build(pending_build_id, tile_pos)
			current_mode = Mode.SELECT

		Mode.DESIGNATE_GATHER:
			var world_pos := _screen_to_world(screen_pos)
			var node := _get_resource_node_at(world_pos)
			if node:
				JobSystem.designate_gather(node)

		Mode.DESIGNATE_HUNT:
			var world_pos := _screen_to_world(screen_pos)
			var animal := _get_animal_at(world_pos)
			if animal:
				JobSystem.designate_hunt(animal)

func _on_left_release(screen_pos: Vector2) -> void:
	if not drag_selecting:
		return
	drag_selecting = false
	if drag_box:
		drag_box.visible = false

	var world_start := _screen_to_world(drag_start)
	var world_end   := _screen_to_world(screen_pos)
	var select_rect := Rect2(world_start, Vector2.ZERO).expand(world_end)

	# Deselect all
	for p in selected_pawns:
		if is_instance_valid(p):
			p.set_selected(false)
	selected_pawns.clear()

	if select_rect.size.length() < 5.0:
		# Single click — select one pawn
		var clicked := _get_pawn_at(_screen_to_world(screen_pos))
		if clicked:
			clicked.set_selected(true)
			selected_pawns.append(clicked)
	else:
		# Drag select
		var all_pawns := get_tree().get_nodes_in_group("pawns")
		for p in all_pawns:
			if select_rect.has_point(p.global_position):
				p.set_selected(true)
				selected_pawns.append(p)

	GameManager.selected_pawns = selected_pawns
	selection_changed.emit(selected_pawns)

func _update_drag(screen_pos: Vector2) -> void:
	drag_rect = Rect2(drag_start, Vector2.ZERO).expand(screen_pos)
	if drag_box:
		drag_box.visible = true
		drag_box.position = drag_rect.position
		drag_box.size = drag_rect.size

func _on_right_click(screen_pos: Vector2) -> void:
	if selected_pawns.is_empty():
		return

	var world_pos := _screen_to_world(screen_pos)
	var tile_pos := WorldGenerator.screen_to_tile(world_pos)

	# Check what was right-clicked
	var resource := _get_resource_node_at(world_pos)
	var animal   := _get_animal_at(world_pos)

	if resource:
		# Order selected pawns to gather
		JobSystem.designate_gather(resource)
		order_issued.emit({ "type": "gather", "target": resource })
	elif animal:
		JobSystem.designate_hunt(animal)
		order_issued.emit({ "type": "hunt", "target": animal })
	else:
		# Move order
		var i := 0
		for pawn in selected_pawns:
			if is_instance_valid(pawn):
				var offset := Vector2(i % 3, i / 3) * 20.0
				pawn.move_to(world_pos + offset)
				i += 1
		order_issued.emit({ "type": "move", "pos": world_pos })

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam:
		return cam.get_screen_center_position() + (screen_pos - get_viewport_rect().size / 2.0) / cam.zoom
	return screen_pos

func _get_pawn_at(world_pos: Vector2) -> Pawn:
	var pawns := get_tree().get_nodes_in_group("pawns")
	for p in pawns:
		if p.global_position.distance_to(world_pos) < 18.0:
			return p as Pawn
	return null

func _get_resource_node_at(world_pos: Vector2) -> Node2D:
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = 2  # resource layer
	var results := space.intersect_point(query, 3)
	if results.size() > 0:
		return results[0]["collider"] as Node2D
	return null

func _get_animal_at(world_pos: Vector2) -> Node2D:
	var animals := get_tree().get_nodes_in_group("wildlife")
	for a in animals:
		if a.global_position.distance_to(world_pos) < 20.0:
			return a as Node2D
	return null

func set_build_mode(building_id: String) -> void:
	current_mode = Mode.BUILD
	pending_build_id = building_id

func set_designate_mode(mode: Mode) -> void:
	current_mode = mode
