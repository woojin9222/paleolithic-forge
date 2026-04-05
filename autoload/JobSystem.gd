extends Node

## Central job/task queue — RimWorld-style work assignment

# Job types
const JOB_GATHER   := "gather"
const JOB_HAUL     := "haul"
const JOB_BUILD    := "build"
const JOB_CRAFT    := "craft"
const JOB_RESEARCH := "research"
const JOB_HUNT     := "hunt"
const JOB_CHOP     := "chop"
const JOB_MINE     := "mine"
const JOB_COOK     := "cook"
const JOB_REST     := "rest"
const JOB_EAT      := "eat"
const JOB_IDLE     := "idle"

# A job: { type, target (Node or Vector2), data (extra info), priority }
var job_queue: Array = []

signal job_posted(job: Dictionary)
signal job_taken(job: Dictionary, pawn: Node)
signal job_completed(job: Dictionary, pawn: Node)

func _ready() -> void:
	pass

# Post a new job to the queue
func post_job(type: String, target = null, data: Dictionary = {}, priority: int = 5) -> Dictionary:
	var job := {
		"id": randi(),
		"type": type,
		"target": target,
		"data": data,
		"priority": priority,
		"assigned_to": null,
		"posted_at": Time.get_ticks_msec(),
	}
	job_queue.append(job)
	job_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])
	job_posted.emit(job)
	return job

# Pawn requests a job — returns best available job for this pawn
func request_job(pawn: Node) -> Dictionary:
	# First check personal needs (hunger, sleep)
	if pawn.hunger < 20.0:
		# Check if food exists in stockpile
		for food_id in ["cooked_meat", "dried_meat", "berry", "raw_meat", "mushroom"]:
			if GameManager.has_resource(food_id):
				return { "type": JOB_EAT, "target": null, "data": { "food": food_id } }

	if pawn.energy < 15.0:
		return { "type": JOB_REST, "target": null, "data": {} }

	# Find best unassigned job matching pawn skills
	for job: Dictionary in job_queue:
		if job["assigned_to"] != null:
			continue
		if _pawn_can_do(pawn, job):
			job["assigned_to"] = pawn
			job_taken.emit(job, pawn)
			return job

	return { "type": JOB_IDLE, "target": null, "data": {} }

func _pawn_can_do(pawn: Node, job: Dictionary) -> bool:
	match job["type"]:
		JOB_HUNT:
			return pawn.skills.get("hunting", 0) >= 1
		JOB_CRAFT:
			return pawn.skills.get("crafting", 0) >= 1
		JOB_RESEARCH:
			return pawn.skills.get("intelligence", 0) >= 1
		JOB_BUILD:
			return pawn.skills.get("construction", 0) >= 1
		_:
			return true

func complete_job(job: Dictionary, pawn: Node) -> void:
	job_queue.erase(job)
	job_completed.emit(job, pawn)

func cancel_job(job: Dictionary) -> void:
	if job.has("assigned_to") and job["assigned_to"] != null:
		var pawn: Node = job["assigned_to"]
		if is_instance_valid(pawn):
			pawn.current_job = JOB_IDLE
	job_queue.erase(job)

# Called when player designates resources for gathering
func designate_gather(resource_node: Node2D) -> void:
	post_job(JOB_GATHER, resource_node, {}, 5)

# Called when player designates a tree to chop
func designate_chop(tree_node: Node2D) -> void:
	post_job(JOB_CHOP, tree_node, {}, 5)

# Called when player designates a build target
func designate_build(building_id: String, tile_pos: Vector2i) -> void:
	post_job(JOB_BUILD, null, { "building": building_id, "tile": tile_pos }, 8)

# Called for crafting orders
func designate_craft(recipe_id: String) -> void:
	if not GameManager.can_craft(recipe_id):
		return
	post_job(JOB_CRAFT, null, { "recipe": recipe_id }, 6)

# Called for hunt orders
func designate_hunt(animal: Node2D) -> void:
	post_job(JOB_HUNT, animal, {}, 7)

# Haul from world position to stockpile
func designate_haul(item_id: String, amount: int, from_pos: Vector2) -> void:
	post_job(JOB_HAUL, null, { "item": item_id, "amount": amount, "from": from_pos }, 4)
