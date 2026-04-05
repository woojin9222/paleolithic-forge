extends CanvasLayer

## Colony management HUD — pawn panel, stockpile, research, time, alerts

@onready var time_label: Label         = $Root/TopBar/TimeLabel
@onready var day_label: Label          = $Root/TopBar/DayLabel
@onready var season_label: Label       = $Root/TopBar/SeasonLabel
@onready var threat_label: Label       = $Root/TopBar/ThreatLabel
@onready var pawn_list: VBoxContainer  = $Root/SidePanel/PawnList
@onready var stockpile_list: VBoxContainer = $Root/SidePanel/StockpileList
@onready var alert_container: VBoxContainer = $Root/Alerts
@onready var research_bar: ProgressBar = $Root/BottomBar/ResearchBar
@onready var research_label: Label     = $Root/BottomBar/ResearchLabel
@onready var bottom_btns: HBoxContainer = $Root/BottomBar/Buttons

# Mobile bottom bar for touch orders
@onready var mobile_bar: HBoxContainer = $Root/MobileBar if has_node("Root/MobileBar") else null

var pawn_panels: Dictionary = {}  # pawn -> PanelContainer

func _ready() -> void:
	# Connect signals
	GameManager.pawn_added.connect(_on_pawn_added)
	GameManager.pawn_died.connect(_on_pawn_died)
	GameManager.colony_stat_changed.connect(_on_colony_stat_changed)
	GameManager.research_unlocked.connect(_on_research_unlocked)
	TimeManager.time_changed.connect(_on_time_changed)
	TimeManager.day_changed.connect(_on_day_changed)
	TimeManager.season_changed.connect(_on_season_changed)

	if has_node("Root/Alerts"):
		# EventManager might not be in scene tree yet
		call_deferred("_connect_event_manager")

	_refresh_stockpile()
	_refresh_research_bar()

func _connect_event_manager() -> void:
	var em := get_tree().get_first_node_in_group("event_manager")
	if em:
		em.notification.connect(_on_notification)

func _process(_delta: float) -> void:
	_update_pawn_panels()
	_refresh_research_bar()

# ── Time ──
func _on_time_changed(_hour: float) -> void:
	if time_label:
		time_label.text = TimeManager.get_time_string()
		# Color shift: orange at sunrise/sunset, blue at night
		var dark := TimeManager.get_darkness()
		time_label.add_theme_color_override("font_color", Color(1.0 - dark * 0.3, 0.8 - dark * 0.3, 0.5 + dark * 0.4))

func _on_day_changed(day: int) -> void:
	if day_label:
		day_label.text = "Day %d" % day
	if threat_label:
		threat_label.text = "Threat: %s" % ["○○○○○", "●○○○○", "●●○○○", "●●●○○", "●●●●○", "●●●●●"][GameManager.threat_level]

func _on_season_changed(season: String) -> void:
	if season_label:
		season_label.text = season

# ── Pawns ──
func _on_pawn_added(pawn: Node) -> void:
	_create_pawn_panel(pawn)

func _on_pawn_died(pawn: Node) -> void:
	if pawn_panels.has(pawn):
		pawn_panels[pawn].queue_free()
		pawn_panels.erase(pawn)

func _create_pawn_panel(pawn: Node) -> void:
	if not pawn_list:
		return
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 70)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = pawn.pawn_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_lbl)

	# Needs bars (health, hunger, energy)
	for stat_name in ["health", "hunger", "energy"]:
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = stat_name.substr(0, 2).to_upper()
		lbl.custom_minimum_size = Vector2(20, 0)
		lbl.add_theme_font_size_override("font_size", 9)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 100
		bar.value = 80
		bar.custom_minimum_size = Vector2(100, 8)
		bar.name = stat_name + "_bar"
		hbox.add_child(lbl)
		hbox.add_child(bar)
		vbox.add_child(hbox)

	var job_lbl := Label.new()
	job_lbl.name = "job_label"
	job_lbl.text = "Idle"
	job_lbl.add_theme_font_size_override("font_size", 9)
	job_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	vbox.add_child(job_lbl)

	# Click to select pawn
	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func(): _select_pawn(pawn))
	panel.add_child(btn)

	pawn_list.add_child(panel)
	pawn_panels[pawn] = panel

func _update_pawn_panels() -> void:
	for pawn: Node in pawn_panels:
		if not is_instance_valid(pawn):
			continue
		var panel: PanelContainer = pawn_panels[pawn]
		var vbox := panel.get_child(0) as VBoxContainer
		if not vbox:
			continue
		# Update bars
		for stat_name in ["health", "hunger", "energy"]:
			var bar := vbox.find_child(stat_name + "_bar") as ProgressBar
			if bar:
				bar.value = pawn.get(stat_name)
		# Update job
		var job_lbl := vbox.find_child("job_label") as Label
		if job_lbl:
			job_lbl.text = pawn.current_job.capitalize()

		# Highlight if selected
		if pawn in GameManager.selected_pawns:
			panel.add_theme_stylebox_override("panel", _selected_style())
		else:
			panel.remove_theme_stylebox_override("panel")

func _select_pawn(pawn: Node) -> void:
	for p in GameManager.pawns:
		if is_instance_valid(p):
			p.set_selected(false)
	GameManager.selected_pawns.clear()
	if is_instance_valid(pawn):
		pawn.set_selected(true)
		GameManager.selected_pawns = [pawn]
		# Center camera
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("center_on"):
			cam.center_on(pawn.global_position)

# ── Stockpile ──
func _on_colony_stat_changed(stat: String, _value: Variant) -> void:
	if stat == "stockpile":
		_refresh_stockpile()

func _refresh_stockpile() -> void:
	if not stockpile_list:
		return
	for child in stockpile_list.get_children():
		child.queue_free()

	for item_id: String in GameManager.stockpile:
		var amount: int = GameManager.stockpile[item_id]
		if amount <= 0:
			continue
		var hbox := HBoxContainer.new()
		var name_lbl := Label.new()
		var item_data := GameManager.ITEMS_DB.get(item_id, {})
		name_lbl.text = item_data.get("name", item_id)
		name_lbl.add_theme_font_size_override("font_size", 10)
		var amt_lbl := Label.new()
		amt_lbl.text = "x%d" % amount
		amt_lbl.add_theme_font_size_override("font_size", 10)
		amt_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
		hbox.add_child(name_lbl)
		hbox.add_child(amt_lbl)
		stockpile_list.add_child(hbox)

# ── Research ──
func _refresh_research_bar() -> void:
	if not research_bar:
		return
	if GameManager.current_research == "":
		research_bar.value = 0
		if research_label:
			research_label.text = "No Research"
		return
	var tech := GameManager.RESEARCH_TREE.get(GameManager.current_research, {})
	research_bar.max_value = tech.get("cost", 100)
	research_bar.value = GameManager.research_progress
	if research_label:
		research_label.text = tech.get("name", "") + " (%d%%)" % int(GameManager.research_progress / tech.get("cost", 1) * 100)

func _on_research_unlocked(tech_id: String) -> void:
	var tech := GameManager.RESEARCH_TREE.get(tech_id, {})
	_on_notification("Research complete: " + tech.get("name", tech_id), "info")

# ── Alerts / Notifications ──
func _on_notification(message: String, severity: String) -> void:
	if not alert_container:
		return
	var lbl := Label.new()
	lbl.text = message
	lbl.add_theme_font_size_override("font_size", 11)
	match severity:
		"danger":  lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		"warning": lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		_:         lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	alert_container.add_child(lbl)
	# Auto-remove after 5s
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()

func _selected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.6, 0.9, 0.2)
	sb.border_color = Color(0.4, 0.7, 1.0)
	sb.set_border_width_all(1)
	return sb
