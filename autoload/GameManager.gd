extends Node

## Central game state manager (Autoload singleton)

signal stats_changed(stat_name: String, value: float)
signal item_added(item_id: String, amount: int)
signal item_removed(item_id: String, amount: int)
signal player_died()
signal game_paused(paused: bool)

# ── World seed ──
var world_seed: int = 0

# ── Survival Stats (0~100) ──
var health: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var temperature: float = 50.0  # 0=freezing, 50=comfortable, 100=overheating
var stamina: float = 100.0

# Drain rates per second
const HUNGER_DRAIN := 0.08
const THIRST_DRAIN := 0.12
const STAMINA_REGEN := 8.0
const COLD_DAMAGE_RATE := 0.3
const HEAT_DAMAGE_RATE := 0.2
const STARVE_DAMAGE_RATE := 0.5
const DEHYDRATE_DAMAGE_RATE := 0.7

# ── Inventory ──
# { "item_id": amount }
var inventory: Dictionary = {}
const MAX_INVENTORY_SLOTS := 20
const MAX_STACK := 99

# ── Player state ──
var is_near_fire: bool = false
var is_in_shelter: bool = false
var is_sprinting: bool = false
var is_alive: bool = true

# ── Item database ──
# item_id -> { name, description, type, stackable, max_stack }
enum ItemType { RESOURCE, TOOL, WEAPON, FOOD, PLACEABLE }

var ITEMS_DB: Dictionary = {
	"stone": { "name": "Stone", "type": ItemType.RESOURCE, "max_stack": 99 },
	"flint": { "name": "Flint", "type": ItemType.RESOURCE, "max_stack": 99 },
	"wood": { "name": "Wood", "type": ItemType.RESOURCE, "max_stack": 99 },
	"stick": { "name": "Stick", "type": ItemType.RESOURCE, "max_stack": 99 },
	"plant_fiber": { "name": "Plant Fiber", "type": ItemType.RESOURCE, "max_stack": 99 },
	"berry": { "name": "Berry", "type": ItemType.FOOD, "max_stack": 30 },
	"raw_meat": { "name": "Raw Meat", "type": ItemType.FOOD, "max_stack": 10 },
	"cooked_meat": { "name": "Cooked Meat", "type": ItemType.FOOD, "max_stack": 10 },
	"hide": { "name": "Animal Hide", "type": ItemType.RESOURCE, "max_stack": 20 },
	"bone": { "name": "Bone", "type": ItemType.RESOURCE, "max_stack": 30 },
	"stone_axe": { "name": "Stone Axe", "type": ItemType.TOOL, "max_stack": 1 },
	"stone_pickaxe": { "name": "Stone Pickaxe", "type": ItemType.TOOL, "max_stack": 1 },
	"stone_spear": { "name": "Stone Spear", "type": ItemType.WEAPON, "max_stack": 1 },
	"hand_axe": { "name": "Hand Axe", "type": ItemType.TOOL, "max_stack": 1 },
	"campfire": { "name": "Campfire", "type": ItemType.PLACEABLE, "max_stack": 5 },
	"lean_to": { "name": "Lean-to Shelter", "type": ItemType.PLACEABLE, "max_stack": 3 },
}

# ── Crafting Recipes ──
# { result_id: { ingredients: {item_id: amount}, tool_required: "", forge_minigame: bool } }
var RECIPES: Dictionary = {
	"hand_axe": {
		"ingredients": { "stone": 2, "flint": 1 },
		"forge_minigame": true,
	},
	"stone_axe": {
		"ingredients": { "stone": 1, "stick": 2, "plant_fiber": 1 },
		"forge_minigame": true,
	},
	"stone_pickaxe": {
		"ingredients": { "stone": 2, "stick": 2, "plant_fiber": 1 },
		"forge_minigame": true,
	},
	"stone_spear": {
		"ingredients": { "flint": 1, "stick": 3, "plant_fiber": 1 },
		"forge_minigame": true,
	},
	"campfire": {
		"ingredients": { "stone": 5, "wood": 3, "stick": 2 },
		"forge_minigame": false,
	},
	"lean_to": {
		"ingredients": { "wood": 6, "stick": 4, "plant_fiber": 3 },
		"forge_minigame": false,
	},
	"cooked_meat": {
		"ingredients": { "raw_meat": 1 },
		"forge_minigame": false,
		"near_fire": true,
	},
}

func _ready() -> void:
	randomize()
	if world_seed == 0:
		world_seed = randi()

func _process(delta: float) -> void:
	if not is_alive:
		return
	_update_survival(delta)

func _update_survival(delta: float) -> void:
	# Drain hunger and thirst
	hunger = max(0.0, hunger - HUNGER_DRAIN * delta)
	thirst = max(0.0, thirst - THIRST_DRAIN * delta)
	stats_changed.emit("hunger", hunger)
	stats_changed.emit("thirst", thirst)

	# Stamina regen when not sprinting
	if not is_sprinting:
		stamina = min(100.0, stamina + STAMINA_REGEN * delta)
		stats_changed.emit("stamina", stamina)

	# Temperature effects
	var ambient := TimeManager.get_ambient_temperature() if is_instance_valid(TimeManager) else 50.0
	var warmth_bonus := 20.0 if is_near_fire else 0.0
	var shelter_bonus := 10.0 if is_in_shelter else 0.0
	temperature = lerp(temperature, ambient + warmth_bonus + shelter_bonus, delta * 0.5)
	temperature = clamp(temperature, 0.0, 100.0)
	stats_changed.emit("temperature", temperature)

	# Damage from extreme conditions
	if hunger <= 0.0:
		health -= STARVE_DAMAGE_RATE * delta
	if thirst <= 0.0:
		health -= DEHYDRATE_DAMAGE_RATE * delta
	if temperature < 15.0:
		health -= COLD_DAMAGE_RATE * delta * (1.0 - temperature / 15.0)
	if temperature > 85.0:
		health -= HEAT_DAMAGE_RATE * delta * ((temperature - 85.0) / 15.0)

	health = clamp(health, 0.0, 100.0)
	stats_changed.emit("health", health)

	if health <= 0.0:
		is_alive = false
		player_died.emit()

# ── Inventory methods ──
func add_item(item_id: String, amount: int = 1) -> bool:
	if not ITEMS_DB.has(item_id):
		return false
	var max_s: int = ITEMS_DB[item_id].get("max_stack", MAX_STACK)
	var current: int = inventory.get(item_id, 0)
	if current + amount > max_s and _get_total_slots() >= MAX_INVENTORY_SLOTS:
		return false
	inventory[item_id] = current + amount
	item_added.emit(item_id, amount)
	return true

func remove_item(item_id: String, amount: int = 1) -> bool:
	var current: int = inventory.get(item_id, 0)
	if current < amount:
		return false
	current -= amount
	if current <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = current
	item_removed.emit(item_id, amount)
	return true

func has_item(item_id: String, amount: int = 1) -> bool:
	return inventory.get(item_id, 0) >= amount

func _get_total_slots() -> int:
	return inventory.size()

# ── Crafting ──
func can_craft(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false
	var recipe: Dictionary = RECIPES[recipe_id]
	for item_id: String in recipe["ingredients"]:
		if not has_item(item_id, recipe["ingredients"][item_id]):
			return false
	if recipe.get("near_fire", false) and not is_near_fire:
		return false
	return true

func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var recipe: Dictionary = RECIPES[recipe_id]
	# Consume ingredients
	for item_id: String in recipe["ingredients"]:
		remove_item(item_id, recipe["ingredients"][item_id])
	# Add result
	add_item(recipe_id, 1)
	return true

# ── Food ──
func eat(item_id: String) -> bool:
	if not has_item(item_id):
		return false
	match item_id:
		"berry":
			hunger = min(100.0, hunger + 8.0)
			thirst = min(100.0, thirst + 3.0)
		"raw_meat":
			hunger = min(100.0, hunger + 15.0)
			health = max(0.0, health - 5.0)  # risk of illness
		"cooked_meat":
			hunger = min(100.0, hunger + 35.0)
		_:
			return false
	remove_item(item_id)
	return true

func drink_water() -> void:
	thirst = min(100.0, thirst + 30.0)
	stats_changed.emit("thirst", thirst)

func take_damage(amount: float) -> void:
	health = max(0.0, health - amount)
	stats_changed.emit("health", health)
	if health <= 0.0:
		is_alive = false
		player_died.emit()

func heal(amount: float) -> void:
	health = min(100.0, health + amount)
	stats_changed.emit("health", health)

func reset_game() -> void:
	health = 100.0
	hunger = 100.0
	thirst = 100.0
	temperature = 50.0
	stamina = 100.0
	inventory.clear()
	is_alive = true
	is_near_fire = false
	is_in_shelter = false
