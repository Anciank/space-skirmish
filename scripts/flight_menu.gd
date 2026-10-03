class_name FlightMenu
extends Control
## Native, keyboard/gamepad-accessible front end in a responsive 1280x720 canvas.

signal launch_requested
signal resume_requested
signal restart_requested
signal title_requested
signal quit_requested

const INK := Color("080c0f")
const PANEL := Color(0.045, 0.06, 0.07, 0.85)
const LINE := Color("37464c")
const WHITE := Color("d2dadd")
const MUTED := Color("88989e")
const CYAN := Color("8db3bb")
const AMBER := Color("cda56d")
const BLUE := Color("7eaab4")
const RED := Color("d1796b")
const CANVAS := Vector2(1280, 720)

var page := "title"
var _return_page := "title"
var _frame: Control
var _first: Control
var _time := 0.0
var _save_status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = Control.new()
	_frame.name = "MenuCanvas"
	_frame.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_frame.size = CANVAS
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	theme = _make_theme()
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	L10n.language_changed.connect(_on_language_changed)
	resized.connect(_layout)
	_layout()
	hide()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _layout() -> void:
	if _frame == null:
		return
	var factor := minf(size.x / CANVAS.x, size.y / CANVAS.y)
	_frame.scale = Vector2.ONE * factor
	_frame.position = (size - CANVAS * factor) * 0.5


func _draw() -> void:
	if not visible:
		return
	# Keep the actual 3D world visible, with a dark wash for readable instruments.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.022, 0.026, 0.46 if page == "title" else 0.94))
	if page == "title":
		var factor := _frame.scale.x
		draw_rect(Rect2(_frame.position + Vector2(42, 96) * factor, Vector2(464, 538) * factor), Color(0.02, 0.028, 0.035, 0.62))


func _begin(next_page: String) -> void:
	page = next_page
	_first = null
	_save_status = null
	for child in _frame.get_children():
		_frame.remove_child(child)
		child.queue_free()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_label("AZURE  /  FLEET OPERATIONS", Vector2(64, 39), 15, WHITE, 680, 26)
	_label("SECTOR 09     /     TACTICAL LINK ACTIVE", Vector2(842, 39), 13, MUTED, 374, 26)
	_rule(Vector2(64, 78), Vector2(1152, 1))
	_rule(Vector2(64, 658), Vector2(1152, 1))
	_label("STAR SKIRMISH", Vector2(64, 676), 12, MUTED, 500, 26)
	_label("MOUSE + KEYBOARD  /  GAMEPAD", Vector2(858, 676), 12, MUTED, 358, 26)


func _focus_first() -> void:
	_apply_focus.call_deferred()


func _apply_focus() -> void:
	if visible and is_instance_valid(_first) and _first.is_inside_tree():
		_first.grab_focus()


func _on_language_changed() -> void:
	theme = _make_theme()
	if not visible:
		return
	var return_page := _return_page
	var focus_path := NodePath()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _frame.is_ancestor_of(focused):
		focus_path = _frame.get_path_to(focused)
	match page:
		"settings": show_settings()
		"controls": show_controls()
		"pause": show_pause()
		"results": show_results()
		"credits": show_credits()
		_: show_title()
	_return_page = return_page
	if not focus_path.is_empty():
		var replacement := _frame.get_node_or_null(focus_path) as Control
		if replacement != null:
			_first = replacement
			_focus_first()


func show_title() -> void:
	_begin("title")
	_label("01   /   DEPLOYMENT AUTHORIZED", Vector2(64, 119), 13, CYAN, 384, 28)
	_label("STAR\nSKIRMISH", Vector2(61, 168), 54, WHITE, 387, 132)
	_rule(Vector2(64, 304), Vector2(384, 1))
	_label("AZ-00  /  COMBAT CORVETTE", Vector2(64, 327), 15, WHITE, 384, 28)
	_label("Twin autocannons. Independent maneuvering thrusters.\nShielded hull. Afterburner reserve.", Vector2(64, 364), 14, MUTED, 384, 62, true)
	_button("DEPLOY VESSEL     >", Vector2(64, 438), Vector2(384, 50), func(): launch_requested.emit(), true, "Deploy")
	_button("FLIGHT HANDBOOK", Vector2(64, 508), Vector2(186, 48), show_controls, false, "Handbook")
	_button("SETTINGS", Vector2(262, 508), Vector2(186, 48), show_settings, false, "Settings")
	_button("QUIT", Vector2(64, 575), Vector2(110, 36), func(): quit_requested.emit(), false, "Quit")
	_button("CREDITS", Vector2(186, 575), Vector2(110, 36), show_credits, false, "Credits")
	_label("ENTER / A  SELECT     ·     ARROWS / D-PAD  NAVIGATE", Vector2(318, 584), 11, MUTED, 384, 42, true)

	_panel(Vector2(720, 318), Vector2(496, 324))
	_label("OPERATION / REMNANT FIELD", Vector2(744, 336), 13, CYAN, 448, 28)
	var ratio := _label("", Vector2(744, 364), 28, WHITE, 132, 44)
	ratio.name = "SquadronRatio"
	ratio.text_direction = Control.TEXT_DIRECTION_LTR
	_update_squadron_ratio()
	_label("CORVETTE ENGAGEMENT", Vector2(900, 374), 14, MUTED, 292, 30)
	_label("05:00 ENGAGEMENT     /     4 SEC REDEPLOY", Vector2(744, 410), 12, AMBER, 448, 26)
	_label("Outscore Crimson before the clock runs out.\nShields recover. Hull damage stays with you.", Vector2(744, 439), 14, MUTED, 448, 56, true)
	_npc_count("ALLY NPCS", "ally_count", "AllyCount", Vector2(744, 503),
		GameSettings.MIN_ALLY_COUNT, GameSettings.MAX_ALLY_COUNT)
	_npc_count("ENEMY NPCS", "enemy_count", "EnemyCount", Vector2(980, 503),
		GameSettings.MIN_ENEMY_COUNT, GameSettings.MAX_ENEMY_COUNT)
	_label("PILOT DIFFICULTY", Vector2(744, 575), 11, MUTED, 448, 22)
	for i in GameSettings.DIFFICULTIES.size():
		var index := i
		var selected := int(GameSettings.get_value("difficulty")) == i
		_button(GameSettings.DIFFICULTIES[i], Vector2(744 + i * 151, 603), Vector2(139, 34), func():
			GameSettings.set_value("difficulty", index)
			show_title()
			_first = _frame.get_node("Difficulty%d" % index)
			_focus_first()
		, selected, "Difficulty%d" % i)
	_focus_first()


func show_pause() -> void:
	_begin("pause")
	_label("02   /   FLIGHT INTERRUPTED", Vector2(64, 120), 13, AMBER, 384, 28)
	_label("HOLDING\nPOSITION", Vector2(60, 166), 54, WHITE, 388, 152)
	_label("Simulation paused. All vessels held.", Vector2(64, 345), 17, MUTED, 384, 38)
	_button("RESUME FLIGHT     >", Vector2(64, 390), Vector2(384, 54), func(): resume_requested.emit(), true, "Resume")
	_button("SETTINGS", Vector2(64, 456), Vector2(186, 46), show_settings, false, "Settings")
	_button("HANDBOOK", Vector2(262, 456), Vector2(186, 46), show_controls, false, "Handbook")
	_button("RESTART SORTIE", Vector2(64, 514), Vector2(384, 46), func(): restart_requested.emit(), false, "Restart")
	_button("RETURN TO COMMAND", Vector2(64, 572), Vector2(384, 46), func(): title_requested.emit(), false, "ReturnTitle")
	_draw_standings(Vector2(584, 158), false)
	_focus_first()


func show_results() -> void:
	_begin("results")
	var result := "DRAW"
	var tint := AMBER
	if GameMatch.winner == GameConfig.TEAM_BLUE:
		result = "VICTORY"
		tint = CYAN
	elif GameMatch.winner == GameConfig.TEAM_RED:
		result = "DEFEAT"
		tint = RED
	_label("03   /   SORTIE COMPLETE", Vector2(64, 120), 13, AMBER, 384, 28)
	_label(result, Vector2(60, 170), 54, tint, 388, 84)
	_label(L10n.text("%02d  /  %02d") % [GameMatch.scores[0], GameMatch.scores[1]], Vector2(64, 270), 48, WHITE, 384, 62).text_direction = Control.TEXT_DIRECTION_LTR
	_label("AZURE          CRIMSON", Vector2(64, 334), 13, MUTED, 384, 28)
	var own: Dictionary = GameMatch.pilots.get("YOU", {})
	var shots := float(own.get("shots", 0))
	var accuracy := 100.0 * float(own.get("hits", 0)) / shots if shots > 0.0 else 0.0
	_panel(Vector2(64, 388), Vector2(384, 104))
	_label("YOUR FLIGHT RECORD", Vector2(84, 403), 11, CYAN, 344, 28)
	_label(L10n.text("%d KILLS    %d DEATHS    %.0f%% HIT RATE") % [own.get("kills", 0), own.get("deaths", 0), minf(accuracy, 100.0)], Vector2(84, 435), 15, WHITE, 344, 50, true)
	_button("FLY AGAIN     >", Vector2(64, 521), Vector2(384, 54), func(): restart_requested.emit(), true, "PlayAgain")
	_button("RETURN TO COMMAND", Vector2(64, 587), Vector2(384, 46), func(): title_requested.emit(), false, "ReturnTitle")
	_draw_standings(Vector2(584, 158), true)
	_focus_first()


func _draw_standings(origin: Vector2, complete: bool) -> void:
	_panel(origin, Vector2(632, 458))
	_label("SQUADRON DEBRIEF" if complete else "LIVE SQUADRON STATUS", origin + Vector2(24, 22), 14, CYAN, 584, 28)
	_label("PILOT", origin + Vector2(24, 70), 11, MUTED, 276, 26).name = "StandingsPilotHeader"
	_label("K", origin + Vector2(324, 70), 11, MUTED, 60, 26)
	_label("D", origin + Vector2(394, 70), 11, MUTED, 60, 26)
	_label("DAMAGE", origin + Vector2(474, 70), 11, MUTED, 112, 26)
	_rule(origin + Vector2(24, 100), Vector2(584, 1))
	var scroll := ScrollContainer.new()
	scroll.name = "StandingsScroll"
	scroll.layout_direction = Control.LAYOUT_DIRECTION_LTR
	scroll.position = origin + Vector2(24, 110)
	scroll.size = Vector2(584, 296)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.scroll_vertical_custom_step = 32.0
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.draw_focus_border = true
	scroll.accessibility_name = L10n.text("SQUADRON DEBRIEF" if complete else "LIVE SQUADRON STATUS")
	_frame.add_child(scroll)
	scroll.position = origin + Vector2(24, 110)
	scroll.size = Vector2(584, 296)
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll.gui_input.connect(_standings_input.bind(scroll))
	scroll.focus_neighbor_left = scroll.get_path_to(_frame.get_node("PlayAgain" if complete else "Resume"))
	var rows := Control.new()
	rows.name = "Rows"
	rows.layout_direction = Control.LAYOUT_DIRECTION_LTR
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var y := 0.0
	var last_team := -1
	for row: Dictionary in GameMatch.standings():
		if row.team != last_team:
			last_team = row.team
			_standings_label(GameConfig.team_name(row.team), rows, Vector2(0, y), 11,
				BLUE if row.team == 0 else RED, 562, 26).name = "Team%d" % row.team
			y += 28.0
		var tint := WHITE if row.name == "YOU" else MUTED
		_standings_label("AZ-00  /  YOU" if row.name == "YOU" else L10n.pilot_name(row.name), rows,
			Vector2(0, y), 16, tint, 276, 30).name = "Pilot_" + row.name
		var kills := _standings_label(str(row.kills), rows, Vector2(300, y), 16, tint, 60, 30)
		kills.name = "K_" + row.name
		kills.text_direction = Control.TEXT_DIRECTION_LTR
		var deaths := _standings_label(str(row.deaths), rows, Vector2(370, y), 16, tint, 60, 30)
		deaths.name = "D_" + row.name
		deaths.text_direction = Control.TEXT_DIRECTION_LTR
		var damage := _standings_label("%.0f" % row.damage, rows, Vector2(450, y), 16, tint, 112, 30)
		damage.name = "Damage_" + row.name
		damage.text_direction = Control.TEXT_DIRECTION_LTR
		y += 32.0
	rows.custom_minimum_size = Vector2(562, y + 2.0)
	_label("FINAL RECORD" if complete else "COMBAT CLOCK FROZEN  /  ESC TO RESUME", origin + Vector2(24, 420), 11, MUTED, 584, 28).name = "StandingsFooter"


func _standings_label(caption: String, parent: Control, pos: Vector2, font_size: int,
		tint: Color, width: float, height: float) -> Label:
	var label := _label(caption, Vector2.ZERO, font_size, tint, width, height)
	label.reparent(parent, false)
	label.position = pos
	return label


func _standings_input(event: InputEvent, scroll: ScrollContainer) -> void:
	var movement := 0
	if event.is_action_pressed("ui_down", true):
		movement = 32
	elif event.is_action_pressed("ui_up", true):
		movement = -32
	elif event.is_action_pressed("ui_page_down", true):
		movement = roundi(scroll.size.y - 32.0)
	elif event.is_action_pressed("ui_page_up", true):
		movement = -roundi(scroll.size.y - 32.0)
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_HOME, KEY_END]:
		var bar := scroll.get_v_scroll_bar()
		scroll.scroll_vertical = 0 if event.keycode == KEY_HOME else roundi(bar.max_value - bar.page)
		scroll.accept_event()
		return
	if movement != 0:
		scroll.scroll_vertical += movement
		scroll.accept_event()


func show_controls() -> void:
	if page != "controls" and page != "settings":
		_return_page = page
	_begin("controls")
	_label("VESSEL HANDBOOK", Vector2(60, 116), 36, WHITE, 1156, 50)
	_label("Flight controls, weapon guidance and survivability.", Vector2(64, 172), 16, MUTED, 1152, 38)
	_panel(Vector2(64, 228), Vector2(552, 358))
	_panel(Vector2(640, 228), Vector2(576, 358))
	_label("FLIGHT / KEYBOARD", Vector2(88, 248), 12, CYAN, 504, 26)
	var bindings := [
		["MOUSE", "Aim / pitch and yaw"], ["W / S", "Main thrust / reverse"],
		["A / D · R / F", "Strafe / vertical thrust"], ["Q / E", "Roll"],
		["SHIFT + W", "Afterburner"], ["SPACE / LEFT CLICK", "Fire twin autocannon"],
		["X · C", "Brake drift / auto-level"], ["TAB · V", "Cycle target / change camera"],
		["ESC · BACKSLASH", "Pause / hold scoreboard"],
	]
	for i in bindings.size():
		_label(bindings[i][0], Vector2(88, 286 + i * 30), 12, WHITE, 192, 28)
		_label(bindings[i][1], Vector2(295, 286 + i * 30), 13, MUTED, 297, 28)
	_label("TACTICS / FIRST ENGAGEMENT", Vector2(664, 248), 12, AMBER, 528, 28)
	_label("01   AIM AT THE AMBER LEAD PIP", Vector2(664, 290), 14, WHITE, 528, 28)
	_label("Cannon rounds take time to arrive. Lead moving targets.", Vector2(664, 318), 13, MUTED, 528, 40, true)
	_label("02   TURN YOUR NOSE. KEEP YOUR DRIFT.", Vector2(664, 363), 14, WHITE, 528, 28)
	_label("Strafe through a pass. Hold X to scrub momentum.", Vector2(664, 391), 13, MUTED, 528, 40, true)
	_label("03   BREAK OFF BEFORE YOUR HULL FAILS", Vector2(664, 436), 14, WHITE, 528, 28)
	_label("Shields recover after 3.2 seconds without a hit.\nBreak away with the burner. Avoid dense gravity anchors.", Vector2(664, 464), 13, MUTED, 528, 54, true)
	_label("PAD: right stick aim · triggers thrust · A fire\nLeft stick strafe / roll · B brake · RB lock · Start pause", Vector2(664, 523), 12, CYAN, 528, 56, true)
	_button("<     BACK", Vector2(64, 606), Vector2(180, 36), go_back, true, "Back")
	_label("M RELEASES THE CURSOR DURING FLIGHT", Vector2(690, 617), 11, MUTED, 502, 28)
	_focus_first()


func show_settings() -> void:
	if page != "settings" and page != "controls":
		_return_page = page
	_begin("settings")
	_label("VESSEL SETTINGS", Vector2(60, 116), 36, WHITE, 556, 50)
	_label("Tune your flight. Changes apply immediately.", Vector2(64, 172), 16, MUTED, 552, 44, true)
	_language_selector()
	_panel(Vector2(64, 228), Vector2(552, 348))
	_panel(Vector2(640, 228), Vector2(576, 348))
	_label("CONTROLS", Vector2(88, 248), 12, CYAN, 504, 26)
	_slider("MOUSE SENSITIVITY", "mouse_sensitivity", Vector2(88, 290), 0.25, 3.0, 0.05, "x")
	_slider("FIELD OF VIEW", "field_of_view", Vector2(88, 362), 70.0, 100.0, 1.0, "deg")
	_checkbox("Invert mouse up/down", "invert_y", Vector2(88, 438), "Also reverses gamepad vertical aim.")
	_checkbox("Invert Q/E roll", "invert_roll", Vector2(351, 438))
	_checkbox("Camera shake", "camera_shake", Vector2(88, 480))
	_checkbox("Flight hints", "show_hints", Vector2(351, 480))
	_checkbox("Fullscreen", "fullscreen", Vector2(88, 522))
	_label("AUDIO MIX", Vector2(664, 248), 12, CYAN, 528, 26)
	_slider("MASTER VOLUME", "master_volume", Vector2(664, 290), 0.0, 1.0, 0.05, "%")
	_slider("WEAPONS / FEEDBACK", "sfx_volume", Vector2(664, 356), 0.0, 1.0, 0.05, "%")
	_slider("ENGINE", "engine_volume", Vector2(664, 422), 0.0, 1.0, 0.05, "%")
	_slider("MUSIC", "music_volume", Vector2(664, 488), 0.0, 1.0, 0.05, "%")
	_button("<     BACK", Vector2(64, 606), Vector2(180, 36), go_back, true, "Back")
	_button("RESTORE DEFAULTS", Vector2(260, 606), Vector2(210, 36), func():
		GameSettings.reset_to_defaults()
		show_settings()
	, false, "Defaults")
	_save_status = _label("PREFERENCES SAVED ON THIS DEVICE", Vector2(794, 617), 11, MUTED, 422, 28)
	_update_save_status()
	_focus_first()


func go_back() -> void:
	Sfx.play_ui("ui_back")
	if page == "settings" or page == "controls" or page == "credits":
		match _return_page:
			"pause": show_pause()
			"results": show_results()
			_: show_title()
	elif page == "pause":
		resume_requested.emit()
	elif page == "results":
		title_requested.emit()


func show_credits() -> void:
	if page != "credits":
		_return_page = page
	_begin("credits")
	_label(L10n.text("STAR SKIRMISH / %s") % ProjectSettings.get_setting("application/config/version", ""), Vector2(60, 116), 42, WHITE, 1156, 60)
	_label("Ships, scenery, effects, music and sound created procedurally for this game.", Vector2(64, 179), 16, MUTED, 1152, 38)
	_label(L10n.text("POWERED BY GODOT / %s") % Engine.get_version_info().string, Vector2(64, 224), 13, CYAN, 1152, 28)
	_panel(Vector2(64, 262), Vector2(1152, 314))
	var scroll := ScrollContainer.new()
	scroll.layout_direction = Control.LAYOUT_DIRECTION_LTR
	scroll.position = Vector2(84, 282)
	scroll.size = Vector2(1112, 274)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(scroll)
	scroll.position = Vector2(84, 282)
	scroll.size = Vector2(1112, 274)
	var notice := RichTextLabel.new()
	notice.name = "EngineLicense"
	notice.fit_content = true
	notice.selection_enabled = true
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.add_theme_font_size_override("normal_font_size", 15)
	notice.add_theme_font_override("normal_font", L10n.font)
	notice.text_direction = Control.TEXT_DIRECTION_AUTO
	notice.add_theme_color_override("default_color", MUTED)
	notice.text = Engine.get_license_text() + L10n.text("\n\nAdditional engine component notices are included in the game's licenses folder.") + "\n\n" + L10n.font_notices()
	scroll.add_child(notice)
	_button("<     BACK", Vector2(64, 606), Vector2(180, 36), go_back, true, "Back")
	_focus_first()


func _update_squadron_ratio() -> void:
	var ratio := _frame.get_node_or_null("SquadronRatio") as Label
	if ratio != null:
		ratio.text = "%d : %d" % [int(GameSettings.get_value("ally_count")) + 1,
			int(GameSettings.get_value("enemy_count"))]


func _npc_count(caption: String, key: String, node_name: String, pos: Vector2,
		low: int, high: int) -> void:
	_label(caption, pos, 12, MUTED, 212, 24)
	var spin := SpinBox.new()
	spin.name = node_name
	spin.layout_direction = Control.LAYOUT_DIRECTION_LTR
	spin.position = pos + Vector2(0, 26)
	spin.size = Vector2(212, 40)
	spin.min_value = low
	spin.max_value = high
	spin.step = 1.0
	spin.value = int(GameSettings.get_value(key))
	spin.editable = false
	spin.localize_numeral_system = false
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.focus_mode = Control.FOCUS_ALL
	spin.clip_contents = true
	spin.accessibility_name = L10n.text(caption)
	# SpinBox's read-only mode also disables its native arrow buttons. Keep
	# the value read-only and provide explicit, fully bounded +/- controls.
	spin.add_theme_constant_override("buttons_width", 0)
	spin.add_theme_constant_override("set_min_buttons_width_from_icons", 0)
	spin.add_theme_constant_override("field_and_buttons_separation", 0)
	_frame.add_child(spin)
	spin.position = pos + Vector2(0, 26)
	spin.size = Vector2(212, 40)
	var field := spin.get_line_edit()
	field.focus_mode = Control.FOCUS_NONE
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.context_menu_enabled = false
	field.selecting_enabled = false
	field.virtual_keyboard_enabled = false
	field.text_direction = Control.TEXT_DIRECTION_LTR
	# Digits share one bundled face with the other numeric readouts. This
	# prevents unrelated fallback ascents from enlarging the fixed control.
	field.add_theme_font_override("font", _heading_font("0123456789"))
	field.add_theme_font_size_override("font_size", 22)
	field.add_theme_color_override("font_uneditable_color", WHITE)
	var count_box := _box(PANEL, LINE)
	count_box.content_margin_top = 1
	count_box.content_margin_bottom = 1
	field.add_theme_stylebox_override("normal", count_box)
	field.add_theme_stylebox_override("read_only", count_box)
	for increment: int in [-1, 1]:
		var change := increment
		var button := _button("-" if change < 0 else "+", Vector2.ZERO, Vector2(42, 40), func():
			spin.grab_focus()
			spin.value += change
		, false, "Decrease" if change < 0 else "Increase")
		button.reparent(spin, false)
		button.position = Vector2(0 if change < 0 else 170, 0)
		button.focus_mode = Control.FOCUS_NONE
		button.accessibility_name = spin.accessibility_name + (" -1" if change < 0 else " +1")
		button.add_theme_font_override("font", _heading_font("+-"))
		button.add_theme_font_size_override("font_size", 20)
	spin.size = Vector2(212, 40)
	var focus_ring := Panel.new()
	focus_ring.name = "FocusRing"
	focus_ring.size = spin.size
	focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_ring.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), WHITE, 2))
	spin.add_child(focus_ring)
	focus_ring.hide()
	spin.gui_input.connect(_npc_count_input.bind(spin))
	spin.focus_entered.connect(func():
		focus_ring.show()
		Sfx.play_ui("ui_focus", -24.0)
	)
	spin.focus_exited.connect(focus_ring.hide)
	spin.value_changed.connect(func(value: float):
		GameSettings.set_value(key, int(value))
		_update_squadron_ratio()
	)


func _npc_count_input(event: InputEvent, spin: SpinBox) -> void:
	if event.is_action_pressed("ui_up", true):
		spin.value += spin.step
		spin.accept_event()
	elif event.is_action_pressed("ui_down", true):
		spin.value -= spin.step
		spin.accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spin.grab_focus()


func _slider(caption: String, key: String, pos: Vector2, low: float, high: float, step_size: float, unit: String) -> void:
	_label(caption, pos, 12, MUTED, 376, 25)
	var readout := _label("", pos + Vector2(392, -3), 16, WHITE, 104, 26)
	readout.text_direction = Control.TEXT_DIRECTION_LTR
	var format_value := func(value: float):
		readout.text = "%d%%" % roundi(value * 100.0) if unit == "%" else ("%d°" % roundi(value) if unit == "deg" else "%.2fx" % value)
	var slider := HSlider.new()
	slider.layout_direction = Control.LAYOUT_DIRECTION_LTR
	slider.name = key
	slider.position = pos + Vector2(0, 36)
	slider.size = Vector2(496, 30)
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = float(GameSettings.get_value(key))
	slider.focus_mode = Control.FOCUS_ALL
	slider.accessibility_name = L10n.text(caption)
	_frame.add_child(slider)
	slider.position = pos + Vector2(0, 36)
	slider.size = Vector2(496, 30)
	format_value.call(slider.value)
	slider.value_changed.connect(func(value: float):
		GameSettings.set_value(key, value)
		format_value.call(value)
		_update_save_status()
	)
	if _first == null:
		_first = slider


func _language_selector() -> void:
	_label("INTERFACE LANGUAGE", Vector2(664, 121), 12, CYAN, 528, 25)
	var options := OptionButton.new()
	options.layout_direction = Control.LAYOUT_DIRECTION_LTR
	options.name = "language"
	options.position = Vector2(664, 153)
	options.size = Vector2(528, 43)
	options.fit_to_longest_item = false
	options.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	options.text_direction = Control.TEXT_DIRECTION_AUTO
	options.accessibility_name = L10n.text("INTERFACE LANGUAGE")
	options.tooltip_text = options.accessibility_name
	options.add_theme_font_override("font", L10n.font)
	options.add_theme_font_size_override("font_size", 18)
	_frame.add_child(options)
	var popup := options.get_popup()
	popup.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	popup.theme = theme
	popup.add_theme_font_override("font", L10n.font)
	popup.add_theme_font_size_override("font_size", 18)
	popup.max_size = Vector2i(0, 360)
	var codes := L10n.language_codes()
	for i in codes.size():
		options.add_item(L10n.language_name(codes[i]))
		options.set_item_metadata(i, codes[i])
		popup.set_item_text_direction(i, Control.TEXT_DIRECTION_AUTO)
		if codes[i] == L10n.locale:
			options.select(i)
	# OptionButton updates its internal popup while items are added. Restore
	# the fixed canvas rectangle after those updates, including RTL locales.
	options.position = Vector2(664, 153)
	options.size = Vector2(528, 43)
	options.item_selected.connect(func(index: int):
		Sfx.play_ui("ui_select")
		GameSettings.set_value("language", options.get_item_metadata(index))
		_update_save_status()
	)


func _checkbox(caption: String, key: String, pos: Vector2, tooltip := "") -> void:
	var check := CheckButton.new()
	check.layout_direction = Control.LAYOUT_DIRECTION_LTR
	check.name = key
	check.text = L10n.text(caption)
	check.accessibility_name = check.text
	check.tooltip_text = L10n.text(tooltip) if not tooltip.is_empty() else ""
	check.text_direction = Control.TEXT_DIRECTION_RTL if L10n.is_rtl() else Control.TEXT_DIRECTION_AUTO
	check.clip_text = true
	check.position = pos
	check.size = Vector2(240, 40)
	check.add_theme_font_size_override("font_size", _fit_font(check.text, 16, 176, 30))
	check.button_pressed = bool(GameSettings.get_value(key))
	_frame.add_child(check)
	check.position = pos
	check.size = Vector2(240, 40)
	check.toggled.connect(func(on: bool):
		GameSettings.set_value(key, on)
		Sfx.play_ui()
		_update_save_status()
	)


func _update_save_status() -> void:
	if _save_status != null:
		_save_status.text = L10n.text("PREFERENCES SAVED ON THIS DEVICE" if GameSettings.last_save_error == OK else "COULD NOT SAVE / ACTIVE FOR THIS SESSION")
		_save_status.add_theme_font_size_override("font_size", _fit_font(_save_status.text, 11, _save_status.size.x, _save_status.size.y))
		_save_status.modulate = WHITE if GameSettings.last_save_error == OK else AMBER


func _heading_font(caption: String) -> Font:
	# A complete heading uses one bundled face, so unrelated fallback ascents
	# cannot enlarge every line. Mixed-script text still keeps the full chain.
	var candidates: Array[Font] = [(L10n.font as FontVariation).base_font]
	candidates.append_array(L10n.font.fallbacks)
	for candidate: Font in candidates:
		var covers_text := true
		for index in caption.length():
			var character := caption.unicode_at(index)
			if character <= 32 or character in [0x200c, 0x200d, 0x200e, 0x200f, 0x2068, 0x2069]:
				continue
			if not candidate.has_char(character):
				covers_text = false
				break
		if covers_text:
			return candidate
	return L10n.font


func _fit_font(caption: String, initial: int, width: float, height: float, wrap := false, fitting_font: Font = null) -> int:
	var fitted := initial
	var minimum := mini(initial, 11) if initial < 24 else 24
	var face := fitting_font if fitting_font != null else L10n.font
	while fitted > minimum:
		var measured := face.get_multiline_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, width if wrap else -1.0, fitted)
		if measured.x <= width and measured.y <= height:
			break
		fitted -= 1
	return fitted


func _label(caption: String, pos: Vector2, font_size: int, tint: Color, width := -1.0, height := -1.0, wrap := false) -> Label:
	var label := Label.new()
	label.layout_direction = Control.LAYOUT_DIRECTION_LTR
	label.set_meta("source_text", caption)
	label.text = L10n.text(caption)
	label.position = pos
	var available := CANVAS.x - 64.0 - pos.x if width < 0.0 else width
	var lines := label.text.count("\n") + 1
	var line_height := L10n.font.get_height(font_size) * lines + 3 if height < 0.0 else height
	var face := _heading_font(label.text) if not wrap and lines > 1 and font_size >= 24 else L10n.font
	label.add_theme_font_override("font", face)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if wrap else TextServer.OVERRUN_TRIM_ELLIPSIS
	label.text_direction = Control.TEXT_DIRECTION_RTL if L10n.is_rtl() else Control.TEXT_DIRECTION_AUTO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if L10n.is_rtl() else HORIZONTAL_ALIGNMENT_LEFT
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", _fit_font(label.text, font_size, available, line_height, wrap, face))
	label.add_theme_color_override("font_color", tint)
	# Set the bounds after wrapping and font sizing remove the default-font
	# minimum width. Otherwise a long translated line can leave a wider label.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(label)
	label.position = pos
	label.size = Vector2(available, line_height)
	if wrap:
		# Label accounts for the tallest fallback glyph on each shaped line.
		# Font's generic multiline measurement can underestimate Hindi/Arabic
		# line height, so also fit against the final control's visible lines.
		var fitted := label.get_theme_font_size("font_size")
		while fitted > 11 and label.get_visible_line_count() < label.get_line_count():
			fitted -= 1
			label.add_theme_font_size_override("font_size", fitted)
			label.size = Vector2(available, line_height)
	elif lines > 1:
		# Non-wrapped labels grow to their intrinsic minimum even with clipping
		# enabled. Fit the actual shaped-line metrics before fixing the bounds.
		var fitted := label.get_theme_font_size("font_size")
		var minimum := mini(font_size, 11) if font_size < 24 else 24
		while fitted > minimum and label.get_minimum_size().y > line_height:
			fitted -= 1
			label.add_theme_font_size_override("font_size", fitted)
		label.size = Vector2(available, line_height)
		label.set_deferred("size", Vector2(available, line_height))
	return label


func _button(caption: String, pos: Vector2, dimensions: Vector2, callback: Callable, primary := false, node_name := "") -> Button:
	var button := Button.new()
	button.layout_direction = Control.LAYOUT_DIRECTION_LTR
	button.name = node_name if not node_name.is_empty() else caption
	button.text = L10n.text(caption)
	button.accessibility_name = button.text
	button.text_direction = Control.TEXT_DIRECTION_RTL if L10n.is_rtl() else Control.TEXT_DIRECTION_AUTO
	button.clip_text = true
	button.position = pos
	button.size = dimensions
	button.add_theme_font_size_override("font_size", _fit_font(button.text, 14 if dimensions.y > 40 else 12, dimensions.x - 28, dimensions.y - 6))
	if primary:
		button.add_theme_stylebox_override("normal", _box(Color(0.12, 0.18, 0.20, 0.86), CYAN))
		button.add_theme_stylebox_override("hover", _box(Color(0.18, 0.25, 0.28, 0.95), WHITE))
		button.add_theme_stylebox_override("pressed", _box(Color("24343b"), CYAN))
		button.add_theme_color_override("font_color", WHITE)
		button.add_theme_color_override("font_hover_color", WHITE)
		button.add_theme_color_override("font_pressed_color", WHITE)
		button.add_theme_color_override("font_focus_color", WHITE)
	button.pressed.connect(func():
		Sfx.play_ui("ui_back" if node_name == "Back" or node_name == "ReturnTitle" else "ui_select")
		callback.call()
	)
	button.mouse_entered.connect(func(): Sfx.play_ui("ui_focus", -24.0))
	button.focus_entered.connect(func(): Sfx.play_ui("ui_focus", -24.0))
	_frame.add_child(button)
	button.position = pos
	button.size = dimensions
	if _first == null:
		_first = button
	return button


func _panel(pos: Vector2, dimensions: Vector2) -> void:
	var panel := Panel.new()
	panel.layout_direction = Control.LAYOUT_DIRECTION_LTR
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.025, 0.035, 0.043, 0.86), LINE))
	_frame.add_child(panel)
	panel.position = pos
	panel.size = dimensions


func _rule(pos: Vector2, dimensions: Vector2) -> void:
	var line := ColorRect.new()
	line.layout_direction = Control.LAYOUT_DIRECTION_LTR
	line.position = pos
	line.size = dimensions
	line.color = LINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(line)
	line.position = pos
	line.size = dimensions


func _box(fill: Color, border: Color, thickness := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(thickness)
	box.set_corner_radius_all(0)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box


func _make_theme() -> Theme:
	var skin := Theme.new()
	skin.default_font = L10n.font
	skin.default_font_size = 16
	skin.set_color("font_color", "Button", WHITE)
	skin.set_color("font_hover_color", "Button", CYAN)
	skin.set_color("font_focus_color", "Button", CYAN)
	skin.set_stylebox("normal", "Button", _box(PANEL, LINE))
	skin.set_stylebox("hover", "Button", _box(Color("1b282e"), CYAN))
	skin.set_stylebox("pressed", "Button", _box(Color("26363c"), CYAN))
	var focus := _box(Color(0, 0, 0, 0), WHITE, 1)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	skin.set_stylebox("focus", "Button", focus)
	skin.set_stylebox("focus", "CheckButton", focus)
	skin.set_stylebox("focus", "HSlider", focus)
	skin.set_stylebox("focus", "ScrollContainer", focus)
	var track := _box(Color("111a1f"), LINE)
	var grabber := _box(Color("445b63"), CYAN)
	var highlighted_grabber := _box(Color("5e7780"), WHITE)
	for style: StyleBoxFlat in [track, grabber, highlighted_grabber]:
		style.content_margin_left = 2
		style.content_margin_right = 2
	skin.set_stylebox("scroll", "VScrollBar", track)
	skin.set_stylebox("grabber", "VScrollBar", grabber)
	skin.set_stylebox("grabber_highlight", "VScrollBar", highlighted_grabber)
	skin.set_stylebox("grabber_pressed", "VScrollBar", highlighted_grabber)
	for style in ["normal", "hover", "pressed", "focus"]:
		skin.set_stylebox(style, "OptionButton", skin.get_stylebox(style, "Button"))
	for color_name in ["font_color", "font_hover_color", "font_focus_color"]:
		skin.set_color(color_name, "OptionButton", skin.get_color(color_name, "Button"))
	var popup_panel := _box(Color("10191e"), LINE)
	popup_panel.content_margin_top = 6
	popup_panel.content_margin_bottom = 6
	skin.set_stylebox("panel", "PopupMenu", popup_panel)
	skin.set_stylebox("hover", "PopupMenu", _box(Color("26363c"), CYAN))
	skin.set_color("font_color", "PopupMenu", WHITE)
	skin.set_color("font_hover_color", "PopupMenu", WHITE)
	skin.set_color("font_color", "CheckButton", WHITE)
	skin.set_color("font_hover_color", "CheckButton", CYAN)
	skin.set_stylebox("slider", "HSlider", _box(LINE, LINE))
	skin.set_stylebox("grabber_area", "HSlider", _box(CYAN, CYAN))
	skin.set_stylebox("grabber_area_highlight", "HSlider", _box(WHITE, WHITE))
	return skin
