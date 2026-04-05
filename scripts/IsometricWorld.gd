extends Node2D

## Manages chunk loading/unloading and renders isometric tile world

const CHUNK_SIZE := 32
const TILE_SIZE := 64
const RENDER_DISTANCE := 3  # chunks around player

@onready var player: CharacterBody2D = $Player

var loaded_chunks: Dictionary = {}  # Vector2i -> Node2D (chunk node)
var resource_nodes: Dictionary = {}  # Vector2i -> Array of resource node refs
var _tile_draw_queue: Array = []

# Day/night overlay
var darkness_overlay: ColorRect
var day_night_color := Color(0.05, 0.03, 0.12, 0.0)

func _ready() -> void:
	# Setup darkness overlay on CanvasLayer
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 5
	add_child(canvas_layer)
	darkness_overlay = ColorRect.new()
	darkness_overlay.color = Color(0, 0, 0, 0)
	darkness_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	darkness_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(darkness_overlay)

	# Spawn player at safe location
	var spawn_tile := WorldGenerator.get_spawn_position()
	var spawn_screen := WorldGenerator.tile_to_screen(spawn_tile)
	player.global_position = spawn_screen

	# Initial chunk loading
	_update_chunks()

	TimeManager.time_changed.connect(_on_time_changed)

func _process(_delta: float) -> void:
	_update_chunks()
	queue_redraw()

func _update_chunks() -> void:
	var player_tile := WorldGenerator.screen_to_tile(player.global_position)
	var player_chunk := Vector2i(
		floori(float(player_tile.x) / CHUNK_SIZE),
		floori(float(player_tile.y) / CHUNK_SIZE)
	)

	# Load new chunks
	var needed_chunks: Dictionary = {}
	for cx in range(player_chunk.x - RENDER_DISTANCE, player_chunk.x + RENDER_DISTANCE + 1):
		for cy in range(player_chunk.y - RENDER_DISTANCE, player_chunk.y + RENDER_DISTANCE + 1):
			var chunk_key := Vector2i(cx, cy)
			needed_chunks[chunk_key] = true
			if not loaded_chunks.has(chunk_key):
				_load_chunk(chunk_key)

	# Unload far chunks
	var to_remove: Array = []
	for chunk_key: Vector2i in loaded_chunks:
		if not needed_chunks.has(chunk_key):
			to_remove.append(chunk_key)
	for chunk_key: Vector2i in to_remove:
		_unload_chunk(chunk_key)

func _load_chunk(chunk_key: Vector2i) -> void:
	var chunk_node := Node2D.new()
	chunk_node.name = "Chunk_%d_%d" % [chunk_key.x, chunk_key.y]
	add_child(chunk_node)
	loaded_chunks[chunk_key] = chunk_node

	var res_list: Array = []

	for lx in range(CHUNK_SIZE):
		for ly in range(CHUNK_SIZE):
			var tile_x := chunk_key.x * CHUNK_SIZE + lx
			var tile_y := chunk_key.y * CHUNK_SIZE + ly

			# Spawn resource nodes
			var resources := WorldGenerator.get_resources_at(tile_x, tile_y)
			for res_id: String in resources:
				var res_node := _create_resource_node(res_id, Vector2i(tile_x, tile_y))
				chunk_node.add_child(res_node)
				res_list.append(res_node)

	resource_nodes[chunk_key] = res_list

func _unload_chunk(chunk_key: Vector2i) -> void:
	if loaded_chunks.has(chunk_key):
		var node: Node2D = loaded_chunks[chunk_key]
		node.queue_free()
		loaded_chunks.erase(chunk_key)
	resource_nodes.erase(chunk_key)

func _draw() -> void:
	# Draw tiles for loaded chunks
	for chunk_key: Vector2i in loaded_chunks:
		_draw_chunk(chunk_key)

func _draw_chunk(chunk_key: Vector2i) -> void:
	for lx in range(CHUNK_SIZE):
		for ly in range(CHUNK_SIZE):
			var tile_x := chunk_key.x * CHUNK_SIZE + lx
			var tile_y := chunk_key.y * CHUNK_SIZE + ly
			var biome := WorldGenerator.get_biome_at(tile_x, tile_y)
			var color: Color = WorldGenerator.BIOME_COLORS[biome]

			# Draw isometric diamond
			var screen_pos := WorldGenerator.tile_to_screen(Vector2i(tile_x, tile_y))
			var half_w := TILE_SIZE / 2.0
			var half_h := TILE_SIZE / 4.0

			var points := PackedVector2Array([
				screen_pos + Vector2(0, -half_h),     # top
				screen_pos + Vector2(half_w, 0),       # right
				screen_pos + Vector2(0, half_h),       # bottom
				screen_pos + Vector2(-half_w, 0),      # left
			])
			draw_colored_polygon(points, color)

			# Tile border
			var border_color := color.darkened(0.2)
			for i in range(4):
				draw_line(points[i], points[(i + 1) % 4], border_color, 0.5)

func _create_resource_node(res_id: String, tile_pos: Vector2i) -> Node2D:
	var node := Area2D.new()
	var screen_pos := WorldGenerator.tile_to_screen(tile_pos)
	node.global_position = screen_pos
	node.name = "%s_%d_%d" % [res_id, tile_pos.x, tile_pos.y]

	# Collision shape
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	node.add_child(col)

	# Visual placeholder (colored circle)
	var visual := Sprite2D.new()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(_get_resource_color(res_id))
	var tex := ImageTexture.create_from_image(img)
	visual.texture = tex
	visual.scale = Vector2(1.5, 1.5)
	node.add_child(visual)

	# Attach script behavior via metadata
	node.set_meta("resource_id", res_id)
	node.set_meta("amount", _get_resource_amount(res_id))
	node.set_meta("tile_pos", tile_pos)

	# Add interact method via script
	var script := GDScript.new()
	script.source_code = _get_resource_script(res_id)
	script.reload()
	node.set_script(script)

	return node

func _get_resource_color(res_id: String) -> Color:
	match res_id:
		"stone": return Color(0.5, 0.48, 0.45)
		"flint": return Color(0.3, 0.3, 0.35)
		"wood": return Color(0.45, 0.3, 0.15)
		"stick": return Color(0.55, 0.4, 0.2)
		"plant_fiber": return Color(0.4, 0.6, 0.3)
		"berry": return Color(0.6, 0.15, 0.2)
	return Color.WHITE

func _get_resource_amount(res_id: String) -> int:
	match res_id:
		"wood": return 3
		"stone": return 2
		"flint": return 1
		"berry": return 4
	return 2

func _get_resource_script(_res_id: String) -> String:
	return '''extends Area2D

func interact(player: CharacterBody2D) -> void:
	player.start_gathering(self)

func harvest(player: CharacterBody2D) -> void:
	var res_id: String = get_meta("resource_id")
	var amount: int = get_meta("amount")
	GameManager.add_item(res_id, amount)
	queue_free()
'''

func _on_time_changed(_hour: float) -> void:
	var d := TimeManager.get_darkness()
	darkness_overlay.color = Color(0.02, 0.01, 0.08, d * 0.75)
