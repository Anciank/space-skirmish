class_name FlightMenu
extends Control
## Native, keyboard/gamepad-accessible front end in a responsive 1280x720 canvas.

signal launch_requested
signal resume_requested
signal restart_requested
signal title_requested
signal quit_requested

const INK := Color("080f1a")
const PANEL := Color("101e2e")
const LINE := Color("29435a")
const WHITE := Color("edf4f8")
const MUTED := Color("94adbf")
const CYAN := Color("78e5e0")
const AMBER := Color("efba70")
const BLUE := Color("65b4ff")
const RED := Color("ff8075")
const CANVAS := Vector2(1280, 720)

var page := "title"
var _return_page := "title"
var _frame: Control
var _first: Control
var _time := 0.0
var _save_status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = Control.new()
	_frame.name = "MenuCanvas"
	_frame.size = CANVAS
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	theme = _make_theme()
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.055, 0.09, 0.50 if page == "title" else 0.92))
	for x in range(0, int(size.x), 64):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.5, 0.75, 0.85, 0.025))
	for y in range(0, int(size.y), 64):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.5, 0.75, 0.85, 0.025))
	draw_line(Vector2(0, size.y - 2), Vector2(size.x * 0.32, size.y - 2), CYAN, 2.0)


func _begin(next_page: String) -> void:
	page = next_page
	_first = null
	_save_status = null
	for child in _frame.get_children():
		_frame.remove_child(child)
		child.queue_free()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_label("AZURE / FLIGHT COMMAND", Vector2(64, 39), 15, CYAN)
	_label("SECTOR 09     /     LOCAL SKIRMISH", Vector2(868, 39), 13, MUTED)
	_rule(Vector2(64, 78), Vector2(1152, 1))
	_rule(Vector2(64, 658), Vector2(1152, 1))
	_label("STAR SKIRMISH", Vector2(64, 676), 12, MUTED)
	_label("MOUSE + KEYBOARD  /  GAMEPAD", Vector2(858, 676), 12, MUTED)


func _focus_first() -> void:
	_apply_focus.call_deferred()


func _apply_focus() -> void:
	if visible and is_instance_valid(_first) and _first.is_inside_tree():
		_first.grab_focus()


func show_title() -> void:
	_begin("title")
	_label("01   /   DEPLOYMENT", Vector2(64, 116), 13, AMBER)
	_label("STAR", Vector2(59, 155), 80, WHITE)
	_label("SKIRMISH", Vector2(59, 234), 80, WHITE)
	_label("Own your momentum. Hold the line.", Vector2(64, 342), 22, MUTED)
	_label("A Newtonian dogfight at the edge of the system.", Vector2(64, 381), 15, MUTED)
	_button("DEPLOY SQUADRON     >", Vector2(64, 438), Vector2(384, 58), func(): launch_requested.emit(), true, "Deploy")
	_button("FLIGHT HANDBOOK", Vector2(64, 508), Vector2(186, 48), show_controls, false, "Handbook")
	_button("SETTINGS", Vector2(262, 508), Vector2(186, 48), show_settings, false, "Settings")
	_button("QUIT", Vector2(64, 575), Vector2(110, 36), func(): quit_requested.emit(), false, "Quit")
	_button("CREDITS", Vector2(186, 575), Vector2(110, 36), show_credits, false, "Credits")
	_label("ENTER / A  SELECT     ·     ARROWS / D-PAD  NAVIGATE", Vector2(318, 584), 11, MUTED)

	_panel(Vector2(720, 378), Vector2(496, 252))
	_label("OPERATION / BROKEN ORBIT", Vector2(744, 398), 13, CYAN)
	_label("3 vs 3", Vector2(744, 428), 32, WHITE)
	_label("TEAM SKIRMISH", Vector2(895, 438), 14, MUTED)
	_label("05:00 ROUND     /     4 SEC REDEPLOY", Vector2(744, 474), 12, AMBER)
	_label("Outscore Crimson before the clock runs out.\nShields recover. Hull damage stays with you.", Vector2(744, 500), 14, MUTED)
	_label("PILOT DIFFICULTY", Vector2(744, 553), 11, MUTED)
	for i in GameSettings.DIFFICULTIES.size():
		var index := i
		var selected := int(GameSettings.get_value("difficulty")) == i
		_button(GameSettings.DIFFICULTIES[i], Vector2(744 + i * 151, 575), Vector2(139, 34), func():
			GameSettings.set_value("difficulty", index)
			show_title()
			_first = _frame.get_node("Difficulty%d" % index)
			_focus_first()
		, selected, "Difficulty%d" % i)
	_focus_first()


func show_pause() -> void:
	_begin("pause")
	_label("02   /   FLIGHT INTERRUPTED", Vector2(64, 120), 13, AMBER)
	_label("HOLDING\nPOSITION", Vector2(60, 166), 62, WHITE)
	_label("Your squadron will wait.", Vector2(64, 345), 19, MUTED)
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
	_label("03   /   SORTIE COMPLETE", Vector2(64, 120), 13, AMBER)
	_label(result, Vector2(60, 170), 66, tint)
	_label("%02d  /  %02d" % [GameMatch.scores[0], GameMatch.scores[1]], Vector2(64, 270), 48, WHITE)
	_label("AZURE          CRIMSON", Vector2(64, 334), 13, MUTED)
	var own: Dictionary = GameMatch.pilots.get("YOU", {})
	var shots := float(own.get("shots", 0))
	var accuracy := 100.0 * float(own.get("hits", 0)) / shots if shots > 0.0 else 0.0
	_panel(Vector2(64, 388), Vector2(384, 104))
	_label("YOUR FLIGHT RECORD", Vector2(84, 403), 11, CYAN)
	_label("%d KILLS    %d DEATHS    %.0f%% HIT RATE" % [own.get("kills", 0), own.get("deaths", 0), minf(accuracy, 100.0)], Vector2(84, 435), 15, WHITE)
	_button("FLY AGAIN     >", Vector2(64, 521), Vector2(384, 54), func(): restart_requested.emit(), true, "PlayAgain")
	_button("RETURN TO COMMAND", Vector2(64, 587), Vector2(384, 46), func(): title_requested.emit(), false, "ReturnTitle")
	_draw_standings(Vector2(584, 158), true)
	_focus_first()


func _draw_standings(origin: Vector2, complete: bool) -> void:
	_panel(origin, Vector2(632, 458))
	_label("SQUADRON DEBRIEF" if complete else "LIVE SQUADRON STATUS", origin + Vector2(24, 22), 14, CYAN)
	_label("PILOT", origin + Vector2(24, 70), 11, MUTED)
	_label("K", origin + Vector2(338, 70), 11, MUTED)
	_label("D", origin + Vector2(413, 70), 11, MUTED)
	_label("DAMAGE", origin + Vector2(503, 70), 11, MUTED)
	_rule(origin + Vector2(24, 100), Vector2(584, 1))
	var y := 114.0
	var last_team := -1
	for row: Dictionary in GameMatch.standings():
		if row.team != last_team:
			last_team = row.team
			_label(GameConfig.team_name(row.team), origin + Vector2(24, y), 11, BLUE if row.team == 0 else RED)
			y += 28.0
		var tint := WHITE if row.name == "YOU" else MUTED
		_label("AZ-00  /  YOU" if row.name == "YOU" else row.name, origin + Vector2(24, y), 16, tint)
		_label(str(row.kills), origin + Vector2(338, y), 16, tint)
		_label(str(row.deaths), origin + Vector2(413, y), 16, tint)
		_label("%.0f" % row.damage, origin + Vector2(503, y), 16, tint)
		y += 32.0
	_label("FINAL RECORD" if complete else "COMBAT CLOCK FROZEN  /  ESC TO RESUME", origin + Vector2(24, 420), 11, MUTED)


func show_controls() -> void:
	if page != "controls" and page != "settings":
		_return_page = page
	_begin("controls")
	_label("FLIGHT HANDBOOK", Vector2(60, 116), 42, WHITE)
	_label("Learn the ship. Then make it yours.", Vector2(64, 172), 16, MUTED)
	_panel(Vector2(64, 228), Vector2(552, 358))
	_panel(Vector2(640, 228), Vector2(576, 358))
	_label("FLIGHT / KEYBOARD", Vector2(88, 248), 12, CYAN)
	var bindings := [
		["MOUSE", "Aim / pitch and yaw"], ["W / S", "Main thrust / reverse"],
		["A / D · R / F", "Strafe / vertical thrust"], ["Q / E", "Roll"],
		["SHIFT + W", "Afterburner"], ["SPACE / LEFT CLICK", "Fire twin autocannon"],
		["X · C", "Brake drift / auto-level"], ["TAB · V", "Cycle target / change camera"],
		["ESC · BACKSLASH", "Pause / hold scoreboard"],
	]
	for i in bindings.size():
		_label(bindings[i][0], Vector2(88, 286 + i * 30), 12, WHITE)
		_label(bindings[i][1], Vector2(295, 286 + i * 30), 13, MUTED)
	_label("TACTICS / FIRST SORTIE", Vector2(664, 248), 12, AMBER)
	_label("01   AIM AT THE AMBER LEAD PIP", Vector2(664, 290), 14, WHITE)
	_label("Your bolts take time to arrive. Lead a moving target.", Vector2(664, 318), 13, MUTED)
	_label("02   TURN YOUR NOSE. KEEP YOUR DRIFT.", Vector2(664, 363), 14, WHITE)
	_label("Strafe through a pass. Hold X to scrub momentum.", Vector2(664, 391), 13, MUTED)
	_label("03   BREAK OFF BEFORE YOUR HULL FAILS", Vector2(664, 436), 14, WHITE)
	_label("Shields recover after 3.2 seconds without a hit.\nUse boost to escape. Avoid rocks and gravity wells.", Vector2(664, 464), 13, MUTED)
	_label("PAD: right stick aim · triggers thrust · A fire\nLeft stick strafe / roll · B brake · RB lock · Start pause", Vector2(664, 523), 12, CYAN)
	_button("<     BACK", Vector2(64, 606), Vector2(180, 36), go_back, true, "Back")
	_label("M RELEASES THE CURSOR DURING FLIGHT", Vector2(690, 617), 11, MUTED)
	_focus_first()


func show_settings() -> void:
	if page != "settings" and page != "controls":
		_return_page = page
	_begin("settings")
	_label("SHIP SETTINGS", Vector2(60, 116), 42, WHITE)
	_label("Tune your flight. Changes apply immediately.", Vector2(64, 172), 16, MUTED)
	_panel(Vector2(64, 228), Vector2(552, 348))
	_panel(Vector2(640, 228), Vector2(576, 348))
	_label("CONTROLS", Vector2(88, 248), 12, CYAN)
	_slider("MOUSE SENSITIVITY", "mouse_sensitivity", Vector2(88, 290), 0.25, 3.0, 0.05, "x")
	_slider("FIELD OF VIEW", "field_of_view", Vector2(88, 380), 70.0, 100.0, 1.0, "deg")
	_checkbox("Invert pitch", "invert_y", Vector2(88, 474))
	_checkbox("Camera shake", "camera_shake", Vector2(351, 474))
	_checkbox("Flight hints", "show_hints", Vector2(88, 523))
	_checkbox("Fullscreen", "fullscreen", Vector2(351, 523))
	_label("AUDIO MIX", Vector2(664, 248), 12, CYAN)
	_slider("MASTER VOLUME", "master_volume", Vector2(664, 290), 0.0, 1.0, 0.05, "%")
	_slider("WEAPONS / FEEDBACK", "sfx_volume", Vector2(664, 356), 0.0, 1.0, 0.05, "%")
	_slider("ENGINE", "engine_volume", Vector2(664, 422), 0.0, 1.0, 0.05, "%")
	_slider("MUSIC", "music_volume", Vector2(664, 488), 0.0, 1.0, 0.05, "%")
	_button("<     BACK", Vector2(64, 606), Vector2(180, 36), go_back, true, "Back")
	_button("RESTORE DEFAULTS", Vector2(260, 606), Vector2(210, 36), func():
		GameSettings.reset_to_defaults()
		show_settings()
	, false, "Defaults")
	_save_status = _label("PREFERENCES SAVED ON THIS DEVICE", Vector2(794, 617), 11, MUTED)
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
	_label("STAR SKIRMISH / %s" % ProjectSettings.get_setting("application/config/version", ""), Vector2(60, 116), 42, WHITE)
	_label("Ships, scenery, effects, music and sound created procedurally for this game.", Vector2(64, 179), 16, MUTED)
	_label("POWERED BY GODOT / %s" % Engine.get_version_info().string, Vector2(64, 224), 13, CYAN)
	_panel(Vector2(64, 262), Vector2(1152, 314))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(84, 282)
	scroll.size = Vector2(1112, 274)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(scroll)
	var notice := RichTextLabel.new()
	notice.name = "EngineLicense"
	notice.fit_content = true
	notice.selection_enabled = true
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.add_theme_font_size_override("normal_font_size", 15)
	notice.add_theme_color_override("default_color", MUTED)
	notice.text = Engine.get_license_text() + "\n\nAdditional engine component notices are included in the game's licenses folder."
	scroll.add_child(notice)
	_button("<     BACK", Vector2(64, 606), Vector2(180, 36), go_back, true, "Back")
	_focus_first()


func _slider(caption: String, key: String, pos: Vector2, low: float, high: float, step_size: float, unit: String) -> void:
	_label(caption, pos, 12, MUTED)
	var readout := _label("", pos + Vector2(392, -3), 16, WHITE)
	var format_value := func(value: float):
		readout.text = "%d%%" % roundi(value * 100.0) if unit == "%" else ("%d°" % roundi(value) if unit == "deg" else "%.2fx" % value)
	var slider := HSlider.new()
	slider.name = key
	slider.position = pos + Vector2(0, 36)
	slider.size = Vector2(496, 30)
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = float(GameSettings.get_value(key))
	slider.focus_mode = Control.FOCUS_ALL
	_frame.add_child(slider)
	format_value.call(slider.value)
	slider.value_changed.connect(func(value: float):
		GameSettings.set_value(key, value)
		format_value.call(value)
		_update_save_status()
	)
	if _first == null:
		_first = slider


func _checkbox(caption: String, key: String, pos: Vector2) -> void:
	var check := CheckButton.new()
	check.name = key
	check.text = caption
	check.position = pos
	check.size = Vector2(240, 40)
	check.button_pressed = bool(GameSettings.get_value(key))
	_frame.add_child(check)
	check.toggled.connect(func(on: bool):
		GameSettings.set_value(key, on)
		Sfx.play_ui()
		_update_save_status()
	)


func _update_save_status() -> void:
	if _save_status != null:
		_save_status.text = "PREFERENCES SAVED ON THIS DEVICE" if GameSettings.last_save_error == OK else "COULD NOT SAVE / ACTIVE FOR THIS SESSION"
		_save_status.modulate = WHITE if GameSettings.last_save_error == OK else AMBER


func _label(caption: String, pos: Vector2, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(label)
	return label


func _button(caption: String, pos: Vector2, dimensions: Vector2, callback: Callable, primary := false, node_name := "") -> Button:
	var button := Button.new()
	button.name = node_name if not node_name.is_empty() else caption
	button.text = caption
	button.position = pos
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 14 if dimensions.y > 40 else 12)
	if primary:
		button.add_theme_stylebox_override("normal", _box(CYAN, CYAN))
		button.add_theme_stylebox_override("hover", _box(Color("adf4eb"), Color("adf4eb")))
		button.add_theme_stylebox_override("pressed", _box(Color("51b8b5"), CYAN))
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
		button.add_theme_color_override("font_focus_color", INK)
	button.pressed.connect(func():
		Sfx.play_ui("ui_back" if node_name == "Back" or node_name == "ReturnTitle" else "ui_select")
		callback.call()
	)
	button.mouse_entered.connect(func(): Sfx.play_ui("ui_focus", -24.0))
	button.focus_entered.connect(func(): Sfx.play_ui("ui_focus", -24.0))
	_frame.add_child(button)
	if _first == null:
		_first = button
	return button


func _panel(pos: Vector2, dimensions: Vector2) -> void:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.075, 0.12, 0.92), LINE))
	_frame.add_child(panel)


func _rule(pos: Vector2, dimensions: Vector2) -> void:
	var line := ColorRect.new()
	line.position = pos
	line.size = dimensions
	line.color = LINE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(line)


func _box(fill: Color, border: Color, thickness := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(thickness)
	box.set_corner_radius_all(3)
	box.content_margin_left = 14
	box.content_margin_right = 14
	return box


func _make_theme() -> Theme:
	var skin := Theme.new()
	skin.default_font_size = 16
	skin.set_color("font_color", "Button", WHITE)
	skin.set_color("font_hover_color", "Button", CYAN)
	skin.set_color("font_focus_color", "Button", CYAN)
	skin.set_stylebox("normal", "Button", _box(PANEL, LINE))
	skin.set_stylebox("hover", "Button", _box(Color("183246"), CYAN))
	skin.set_stylebox("pressed", "Button", _box(Color("224657"), CYAN))
	var focus := _box(Color(0, 0, 0, 0), WHITE, 2)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	skin.set_stylebox("focus", "Button", focus)
	skin.set_stylebox("focus", "CheckButton", focus)
	skin.set_stylebox("focus", "HSlider", focus)
	skin.set_color("font_color", "CheckButton", WHITE)
	skin.set_color("font_hover_color", "CheckButton", CYAN)
	skin.set_stylebox("slider", "HSlider", _box(LINE, LINE))
	skin.set_stylebox("grabber_area", "HSlider", _box(CYAN, CYAN))
	skin.set_stylebox("grabber_area_highlight", "HSlider", _box(WHITE, WHITE))
	return skin
