extends Node

## Seed-based procedural world generation using noise

# Biome types
enum Biome {
	WATER,
	SAND,
	GRASSLAND,
	FOREST,
	DENSE_FOREST,
	ROCKY,
	MOUNTAIN,
}

# Biome colors for minimap / debug
const BIOME_COLORS := {
	Biome.WATER: Color(0.15, 0.3, 0.5),
	Biome.SAND: Color(0.76, 0.7, 0.5),
	Biome.GRASSLAND: Color(0.35, 0.55, 0.25),
	Biome.FOREST: Color(0.2, 0.4, 0.15),
	Biome.DENSE_FOREST: Color(0.12, 0.28, 0.1),
	Biome.ROCKY: Color(0.45, 0.42, 0.38),
	Biome.MOUNTAIN: Color(0.55, 0.52, 0.48),
}

# Resource spawn chances per biome: { resource_id: probability_per_tile }
const BIOME_RESOURCES := {
	Biome.GRASSLAND: { "stick": 0.06, "plant_fiber": 0.08, "berry": 0.04, "stone": 0.02 },
	Biome.FOREST: { "wood": 0.15, "stick": 0.1, "plant_fiber": 0.05, "berry": 0.06, "stone": 0.01 },
	Biome.DENSE_FOREST: { "wood": 0.25, "stick": 0.12, "plant_fiber": 0.04, "berry": 0.03 },
	Biome.ROCKY: { "stone": 0.2, "flint": 0.08 },
	Biome.MOUNTAIN: { "stone": 0.3, "flint": 0.15 },
	Biome.SAND: { "stick": 0.02, "stone": 0.01 },
}

const CHUNK_SIZE := 32  # tiles per chunk
const TILE_SIZE := 64   # pixels per tile (isometric)

var noise_elevation: FastNoiseLite
var noise_moisture: FastNoiseLite
var noise_detail: FastNoiseLite

var generated_chunks: Dictionary = {}  # Vector2i -> chunk data
var _rng: RandomNumberGenerator

func _ready() -> void:
	_setup_noise(GameManager.world_seed)

func _setup_noise(seed_val: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_val

	noise_elevation = FastNoiseLite.new()
	noise_elevation.seed = seed_val
	noise_elevation.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_elevation.frequency = 0.008
	noise_elevation.fractal_octaves = 5
	noise_elevation.fractal_lacunarity = 2.0
	noise_elevation.fractal_gain = 0.5

	noise_moisture = FastNoiseLite.new()
	noise_moisture.seed = seed_val + 1000
	noise_moisture.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_moisture.frequency = 0.012
	noise_moisture.fractal_octaves = 4

	noise_detail = FastNoiseLite.new()
	noise_detail.seed = seed_val + 2000
	noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_detail.frequency = 0.05
	noise_detail.fractal_octaves = 2

func get_biome_at(tile_x: int, tile_y: int) -> Biome:
	var elev := (noise_elevation.get_noise_2d(tile_x, tile_y) + 1.0) / 2.0
	var moist := (noise_moisture.get_noise_2d(tile_x, tile_y) + 1.0) / 2.0
	var detail := noise_detail.get_noise_2d(tile_x, tile_y) * 0.1

	elev = clamp(elev + detail, 0.0, 1.0)

	if elev < 0.25:
		return Biome.WATER
	elif elev < 0.32:
		return Biome.SAND
	elif elev < 0.55:
		if moist > 0.6:
			return Biome.FOREST
		return Biome.GRASSLAND
	elif elev < 0.7:
		if moist > 0.55:
			return Biome.DENSE_FOREST
		return Biome.FOREST
	elif elev < 0.82:
		return Biome.ROCKY
	else:
		return Biome.MOUNTAIN

func get_resources_at(tile_x: int, tile_y: int) -> Array:
	var biome := get_biome_at(tile_x, tile_y)
	if not BIOME_RESOURCES.has(biome):
		return []

	var resources: Array = []
	var res_table: Dictionary = BIOME_RESOURCES[biome]

	# Use deterministic RNG per tile
	var tile_hash := hash(Vector2i(tile_x, tile_y))
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = GameManager.world_seed ^ tile_hash

	for res_id: String in res_table:
		if local_rng.randf() < res_table[res_id]:
			resources.append(res_id)

	return resources

## Returns whether a tile is walkable
func is_walkable(tile_x: int, tile_y: int) -> bool:
	var biome := get_biome_at(tile_x, tile_y)
	return biome != Biome.WATER and biome != Biome.MOUNTAIN

## Convert isometric tile coords to screen position
func tile_to_screen(tile_pos: Vector2i) -> Vector2:
	var x := (tile_pos.x - tile_pos.y) * (TILE_SIZE / 2)
	var y := (tile_pos.x + tile_pos.y) * (TILE_SIZE / 4)
	return Vector2(x, y)

## Convert screen position to tile coords
func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var tx := (screen_pos.x / (TILE_SIZE / 2) + screen_pos.y / (TILE_SIZE / 4)) / 2.0
	var ty := (screen_pos.y / (TILE_SIZE / 4) - screen_pos.x / (TILE_SIZE / 2)) / 2.0
	return Vector2i(roundi(tx), roundi(ty))

func get_spawn_position() -> Vector2i:
	# Find a grassland tile near origin
	for radius in range(0, 50):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var biome := get_biome_at(dx, dy)
					if biome == Biome.GRASSLAND:
						return Vector2i(dx, dy)
	return Vector2i.ZERO
