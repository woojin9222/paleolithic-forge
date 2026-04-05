extends Node

## Colony-level game state manager (Autoload singleton)

signal colony_stat_changed(stat: String, value: Variant)
signal pawn_added(pawn: Node)
signal pawn_died(pawn: Node)
signal research_unlocked(tech_id: String)
signal event_triggered(event: Dictionary)
signal game_over(reason: String)

# ── World ──
var world_seed: int = 0

# ── Colony resources (stockpile) ──
# item_id -> amount
var stockpile: Dictionary = {}

# ── Colony stats ──
var colony_day: int = 1
var colony_name: String = "First Hearth"
var is_game_over: bool = false
var threat_level: int = 0  # 0~5, grows over time → harder raids

# ── Pawns ──
var pawns: Array = []        # Array[Pawn]
var selected_pawns: Array = []  # currently selected

# ── Research ──
var unlocked_techs: Array[String] = []
var current_research: String = ""
var research_progress: float = 0.0  # 0~100

# ── Item database ──
enum ItemType { RESOURCE, TOOL, WEAPON, FOOD, PLACEABLE, MEDICINE }

var ITEMS_DB: Dictionary = {
	# Resources
	"stone":        { "name": "Stone",        "type": ItemType.RESOURCE, "max_stack": 999 },
	"flint":        { "name": "Flint",        "type": ItemType.RESOURCE, "max_stack": 999 },
	"wood":         { "name": "Wood",         "type": ItemType.RESOURCE, "max_stack": 999 },
	"stick":        { "name": "Stick",        "type": ItemType.RESOURCE, "max_stack": 999 },
	"plant_fiber":  { "name": "Plant Fiber",  "type": ItemType.RESOURCE, "max_stack": 999 },
	"clay":         { "name": "Clay",         "type": ItemType.RESOURCE, "max_stack": 999 },
	"bone":         { "name": "Bone",         "type": ItemType.RESOURCE, "max_stack": 999 },
	"hide":         { "name": "Animal Hide",  "type": ItemType.RESOURCE, "max_stack": 999 },
	"sinew":        { "name": "Sinew",        "type": ItemType.RESOURCE, "max_stack": 999 },
	"charcoal":     { "name": "Charcoal",     "type": ItemType.RESOURCE, "max_stack": 999 },
	# Food
	"berry":        { "name": "Berries",      "type": ItemType.FOOD, "nutrition": 8,  "max_stack": 99 },
	"mushroom":     { "name": "Mushroom",     "type": ItemType.FOOD, "nutrition": 10, "max_stack": 99 },
	"raw_meat":     { "name": "Raw Meat",     "type": ItemType.FOOD, "nutrition": 12, "max_stack": 30, "rot_days": 2 },
	"cooked_meat":  { "name": "Cooked Meat",  "type": ItemType.FOOD, "nutrition": 30, "max_stack": 30, "rot_days": 5 },
	"dried_meat":   { "name": "Dried Meat",   "type": ItemType.FOOD, "nutrition": 25, "max_stack": 50, "rot_days": 20 },
	"fish":         { "name": "Fish",         "type": ItemType.FOOD, "nutrition": 15, "max_stack": 20, "rot_days": 1 },
	# Tools
	"hand_axe":     { "name": "Hand Axe",     "type": ItemType.TOOL,   "durability": 100, "max_stack": 1 },
	"stone_axe":    { "name": "Stone Axe",    "type": ItemType.TOOL,   "durability": 120, "max_stack": 1 },
	"stone_pick":   { "name": "Stone Pick",   "type": ItemType.TOOL,   "durability": 100, "max_stack": 1 },
	"bone_needle":  { "name": "Bone Needle",  "type": ItemType.TOOL,   "durability": 50,  "max_stack": 1 },
	"clay_pot":     { "name": "Clay Pot",     "type": ItemType.TOOL,   "durability": 80,  "max_stack": 1 },
	# Weapons
	"stone_spear":  { "name": "Stone Spear",  "type": ItemType.WEAPON, "damage": 20, "durability": 80, "max_stack": 1 },
	"bone_club":    { "name": "Bone Club",    "type": ItemType.WEAPON, "damage": 12, "durability": 150, "max_stack": 1 },
	"bow":          { "name": "Bow",          "type": ItemType.WEAPON, "damage": 18, "durability": 100, "max_stack": 1 },
	# Placeables (buildings)
	"campfire":     { "name": "Campfire",     "type": ItemType.PLACEABLE, "max_stack": 5 },
	"lean_to":      { "name": "Lean-to",      "type": ItemType.PLACEABLE, "max_stack": 3 },
	"stockpile_zone":{ "name": "Stockpile",   "type": ItemType.PLACEABLE, "max_stack": 3 },
	"tanning_rack": { "name": "Tanning Rack", "type": ItemType.PLACEABLE, "max_stack": 2 },
	"drying_rack":  { "name": "Drying Rack",  "type": ItemType.PLACEABLE, "max_stack": 2 },
}

# ── Crafting recipes ──
# result_id: { ingredients, station, forge_minigame, research_required }
var RECIPES: Dictionary = {
	"stick":       { "ingredients": { "wood": 1 },                              "station": "",          "forge": false },
	"hand_axe":    { "ingredients": { "stone": 2, "flint": 1 },                 "station": "",          "forge": true  },
	"stone_axe":   { "ingredients": { "stone": 1, "stick": 2, "plant_fiber":1 },"station": "",          "forge": true  },
	"stone_pick":  { "ingredients": { "stone": 2, "stick": 2, "plant_fiber":1 },"station": "",          "forge": true  },
	"stone_spear": { "ingredients": { "flint": 1, "stick": 3, "plant_fiber":1 },"station": "",          "forge": true  },
	"bone_club":   { "ingredients": { "bone": 3, "plant_fiber": 1 },            "station": "",          "forge": false },
	"bone_needle": { "ingredients": { "bone": 1 },                              "station": "",          "forge": false },
	"cooked_meat": { "ingredients": { "raw_meat": 1 },                          "station": "campfire",  "forge": false },
	"dried_meat":  { "ingredients": { "raw_meat": 2, "charcoal": 1 },           "station": "drying_rack","forge": false, "research": "preservation" },
	"clay_pot":    { "ingredients": { "clay": 3 },                              "station": "campfire",  "forge": false, "research": "pottery" },
	"bow":         { "ingredients": { "wood": 2, "stick": 1, "sinew": 2 },      "station": "",          "forge": false, "research": "archery" },
	"campfire":    { "ingredients": { "stone": 5, "wood": 3, "stick": 2 },      "station": "",          "forge": false },
	"lean_to":     { "ingredients": { "wood": 6, "stick": 4, "plant_fiber": 3 },"station": "",          "forge": false },
	"tanning_rack":{ "ingredients": { "wood": 4, "stick": 2, "plant_fiber": 2 },"station": "",          "forge": false, "research": "tanning" },
	"drying_rack": { "ingredients": { "wood": 3, "stick": 3 },                  "station": "",          "forge": false, "research": "preservation" },
}

# ── Research tree ──
var RESEARCH_TREE: Dictionary = {
	"fire_control": { "name": "Fire Control",  "cost": 200, "requires": [],                "unlocks": ["campfire_upgrade"] },
	"tool_craft":   { "name": "Tool Crafting", "cost": 300, "requires": [],                "unlocks": ["stone_axe", "stone_pick"] },
	"hunting":      { "name": "Hunting",       "cost": 400, "requires": ["tool_craft"],    "unlocks": ["stone_spear"] },
	"archery":      { "name": "Archery",       "cost": 600, "requires": ["hunting"],       "unlocks": ["bow"] },
	"tanning":      { "name": "Tanning",       "cost": 350, "requires": ["hunting"],       "unlocks": ["tanning_rack"] },
	"preservation": { "name": "Preservation",  "cost": 450, "requires": ["fire_control"],  "unlocks": ["dried_meat", "drying_rack"] },
	"pottery":      { "name": "Pottery",       "cost": 500, "requires": ["fire_control"],  "unlocks": ["clay_pot"] },
	"agriculture":  { "name": "Agriculture",   "cost": 800, "requires": ["pottery"],       "unlocks": ["crop_field"] },
	"shelter":      { "name": "Shelter Building","cost": 400,"requires": ["tool_craft"],   "unlocks": ["lean_to"] },
}

func _ready() -> void:
	randomize()
	if world_seed == 0:
		world_seed = randi()
	# Start with basic techs
	unlocked_techs = ["fire_control"]
	# Starter resources
	stockpile = {
		"stone": 10, "wood": 8, "stick": 5, "plant_fiber": 6,
		"berry": 8, "flint": 3,
	}

func _process(delta: float) -> void:
	if is_game_over:
		return
	_update_research(delta)
	_check_game_over()

func _update_research(delta: float) -> void:
	if current_research == "":
		return
	# Research speed based on number of pawns assigned to research job
	var researchers := pawns.filter(func(p): return p.current_job == "research")
	if researchers.is_empty():
		return
	var speed := researchers.size() * 5.0  # points per second per researcher
	research_progress += speed * delta
	var tech := RESEARCH_TREE[current_research]
	if research_progress >= tech["cost"]:
		_complete_research()

func _complete_research() -> void:
	unlocked_techs.append(current_research)
	research_unlocked.emit(current_research)
	current_research = ""
	research_progress = 0.0

func start_research(tech_id: String) -> bool:
	if not RESEARCH_TREE.has(tech_id):
		return false
	if unlocked_techs.has(tech_id):
		return false
	var tech := RESEARCH_TREE[tech_id]
	for req: String in tech["requires"]:
		if not unlocked_techs.has(req):
			return false
	current_research = tech_id
	research_progress = 0.0
	return true

func is_tech_unlocked(tech_id: String) -> bool:
	return unlocked_techs.has(tech_id)

func _check_game_over() -> void:
	if pawns.is_empty():
		is_game_over = true
		game_over.emit("All tribe members have perished.")

# ── Stockpile ──
func add_resource(item_id: String, amount: int = 1) -> void:
	stockpile[item_id] = stockpile.get(item_id, 0) + amount
	colony_stat_changed.emit("stockpile", stockpile)

func remove_resource(item_id: String, amount: int = 1) -> bool:
	if stockpile.get(item_id, 0) < amount:
		return false
	stockpile[item_id] -= amount
	if stockpile[item_id] <= 0:
		stockpile.erase(item_id)
	colony_stat_changed.emit("stockpile", stockpile)
	return true

func has_resource(item_id: String, amount: int = 1) -> bool:
	return stockpile.get(item_id, 0) >= amount

func get_resource(item_id: String) -> int:
	return stockpile.get(item_id, 0)

# ── Crafting ──
func can_craft(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false
	var r: Dictionary = RECIPES[recipe_id]
	if r.has("research") and not is_tech_unlocked(r["research"]):
		return false
	for item: String in r["ingredients"]:
		if not has_resource(item, r["ingredients"][item]):
			return false
	return true

func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var r: Dictionary = RECIPES[recipe_id]
	for item: String in r["ingredients"]:
		remove_resource(item, r["ingredients"][item])
	add_resource(recipe_id, 1)
	return true

# ── Pawn management ──
func register_pawn(pawn: Node) -> void:
	if not pawns.has(pawn):
		pawns.append(pawn)
		pawn_added.emit(pawn)

func unregister_pawn(pawn: Node) -> void:
	pawns.erase(pawn)
	selected_pawns.erase(pawn)
	pawn_died.emit(pawn)

func get_idle_pawn() -> Node:
	for p in pawns:
		if p.current_job == "idle":
			return p
	return null

func reset_game() -> void:
	stockpile = { "stone": 10, "wood": 8, "stick": 5, "plant_fiber": 6, "berry": 8, "flint": 3 }
	pawns.clear()
	selected_pawns.clear()
	unlocked_techs = ["fire_control"]
	current_research = ""
	research_progress = 0.0
	colony_day = 1
	threat_level = 0
	is_game_over = false
