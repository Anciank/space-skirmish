extends Node
## Catalogue completeness, real language switching, persistence and shaping.

var _main: Node3D
var _checks := 0
var _failures := 0
var _preferences: Dictionary
var _settings_path: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	_settings_path = GameSettings.storage_path
	GameSettings.storage_path = "user://localization-test-%d.cfg" % Time.get_ticks_usec()
	GameSettings.reset_to_defaults(false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.pause_on_focus_loss = false
	add_child(_main)
	await _frames(3)
	await _catalogue_checks()
	await _switching_checks()
	await _control_preference_checks()
	await _small_settings_checks()
	await _pause_checks()
	_preference_checks()
	_main._show_title()
	_main.queue_free()
	await _frames(2)
	DirAccess.remove_absolute(GameSettings.storage_path)
	DirAccess.remove_absolute(GameSettings.storage_path + ".tmp")
	GameSettings.storage_path = _settings_path
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	print("--- localization: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _catalogue_checks() -> void:
	var codes := L10n.language_codes()
	_check("twelve languages are available by their native names", codes.size() == 12 and L10n.language_name("zh_CN") == "简体中文")
	var english := L10n.catalogue("en")
	var format := RegEx.new()
	format.compile("%(?:[0-9]+)?(?:\\.[0-9]+)?[dsf]|%%")
	for code: String in codes:
		var catalogue := L10n.catalogue(code)
		var complete := catalogue.size() == english.size() and catalogue.size() >= 150
		var formats_ok := true
		var glyphs_ok := true
		var missing := ""
		for source: String in english:
			if not catalogue.has(source) or not catalogue[source] is String or String(catalogue[source]).is_empty():
				complete = false
				continue
			var caption := String(catalogue[source])
			formats_ok = formats_ok and _tokens(format, source) == _tokens(format, caption)
			for index in caption.length():
				var character := caption.unicode_at(index)
				if character <= 32 or character in [0x200c, 0x200d, 0x200e, 0x200f, 0x2068, 0x2069]:
					continue
				if not L10n.font.has_char(character):
					glyphs_ok = false
					missing = "U+%04X" % character
		for index in L10n.language_name(code).length():
			glyphs_ok = glyphs_ok and L10n.font.has_char(L10n.language_name(code).unicode_at(index))
		_check(code + " catalogue covers every display source", complete)
		_check(code + " translations preserve formatting arguments", formats_ok)
		_check(code + " text is covered by the bundled font", glyphs_ok, missing)
		GameSettings.set_value("language", code, false)
		_check(code + " activates translated menus and HUD terms", L10n.locale == code
			and L10n.text("SETTINGS") == catalogue.get("SETTINGS")
			and L10n.text("VESSEL LOST") == catalogue.get("VESSEL LOST")
			and (code == "en" or L10n.text("SETTINGS") != "SETTINGS"))
		_check(code + " keeps unknown text readable", L10n.text("Uncatalogued callsign AZ-99") == "Uncatalogued callsign AZ-99")
	var fonts: Array[Font] = L10n.font.fallbacks.duplicate()
	fonts.append((L10n.font as FontVariation).base_font)
	var portable := fonts.size() == 4
	for font: Font in fonts:
		portable = portable and not (font as FontFile).allow_system_fallback
	_check("all scripts render without system-font dependencies", portable)
	_check("font licenses remain available in the game", L10n.font_notices().contains("SIL OPEN FONT LICENSE"))
	var fallback := Translation.new()
	fallback.locale = "en"
	fallback.add_message("English-only fallback fixture", "Readable English fallback")
	TranslationServer.add_translation(fallback)
	GameSettings.set_value("language", "ja", false)
	_check("a missing localized entry falls back to English", L10n.text("English-only fallback fixture") == "Readable English fallback")
	TranslationServer.remove_translation(fallback)


func _tokens(format: RegEx, value: String) -> Array[String]:
	var tokens: Array[String] = []
	for match_result: RegExMatch in format.search_all(value):
		tokens.append(match_result.get_string())
	return tokens


func _switching_checks() -> void:
	var menu: FlightMenu = _main.menu
	for code: String in L10n.language_codes():
		GameSettings.set_value("language", code, false)
		menu.show_title()
		await _frames(2)
		_npc_selector_check(menu, code)
		var layout_ok := _inside_canvas(menu)
		_check(code + " command button uses the selected language", menu._frame.get_node("Settings").text == L10n.text("SETTINGS"))
		await _wrapped_body_check(menu, code, "title", 3)
		await _heading_check(menu, code, "title", "STAR\nSKIRMISH", Rect2(61, 168, 387, 132), "AZ-00  /  COMBAT CORVETTE")
		menu.show_pause()
		await _frames(2)
		await _heading_check(menu, code, "pause", "HOLDING\nPOSITION", Rect2(60, 166, 388, 152), "Simulation paused. All vessels held.")
		menu.show_settings()
		await _frames(2)
		_settings_controls_check(menu, code)
		var options := menu._frame.get_node("language") as OptionButton
		_check(code + " language selector retains its selection", options.item_count == 12
			and options.get_item_metadata(options.selected) == code and options.text == L10n.language_name(code))
		layout_ok = layout_ok and _inside_canvas(menu)
		menu.show_controls()
		await _frames(2)
		layout_ok = layout_ok and _inside_canvas(menu)
		await _wrapped_body_check(menu, code, "handbook", 4)
		menu.show_results()
		await _frames(2)
		layout_ok = layout_ok and _inside_canvas(menu)
		await _wrapped_body_check(menu, code, "results", 1)
		_check(code + " menu controls stay inside the canvas", layout_ok)
		var hud: Control = _main.hud
		var line: TextLine = hud._shaped_text(L10n.text("SHIELD"), 16)
		_check(code + " HUD shapes text in the selected direction", line.get_line_width() > 0.0
			and line.direction == (TextServer.DIRECTION_RTL if code == "ar" else TextServer.DIRECTION_LTR))
		var collision := {"killer": "", "victim": "YOU", "cause": "COLLISION"}
		_check(code + " existing combat events are displayed in the active language", hud._feed_text(collision).contains(L10n.text("COLLISION"))
			and hud._feed_text(collision).contains(L10n.text("YOU")))
		_check(code + " pilot IDs stay stable behind the translated display", L10n.pilot_name("CR-01").contains("CR-01"))
	await _wrapped_guard_check(menu)
	GameSettings.set_value("language", "ar", false)
	_check("Arabic mixed-script callsigns are direction-isolated", L10n.pilot_name("AZ-01") == "\u2068AZ-01\u2069")
	menu.show_title()
	menu.show_settings()
	(menu._frame.get_node("language") as Control).grab_focus()
	GameSettings.set_value("language", "zh_CN", false)
	await _frames(3)
	_check("live language switching preserves the settings page and focus", menu.page == "settings"
		and get_viewport().gui_get_focus_owner() == menu._frame.get_node("language"))
	menu.go_back()
	_check("switching language preserves return navigation", menu.page == "title")


func _settings_controls_check(menu: FlightMenu, code: String) -> void:
	var complete := true
	var controls: Array[Control] = []
	var control_area := Rect2(88, 438, 503, 124)
	for pair: Array in [["invert_y", "Invert mouse up/down"], ["invert_roll", "Invert Q/E roll"],
			["camera_shake", "Camera shake"], ["show_hints", "Flight hints"], ["fullscreen", "Fullscreen"]]:
		var check := menu._frame.get_node_or_null(pair[0]) as CheckButton
		if check == null:
			complete = false
			continue
		controls.append(check)
		var font := check.get_theme_font("font")
		var font_size := check.get_theme_font_size("font_size")
		var text_size := font.get_string_size(check.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		complete = complete and check.text == L10n.text(pair[1]) and check.accessibility_name == check.text \
			and check.button_pressed == bool(GameSettings.get_value(pair[0])) \
			and control_area.encloses(Rect2(check.position, check.size)) \
			and text_size.x <= 176.0 and text_size.y <= 30.0 and font_size >= 11 \
			and check.get_minimum_size().y <= check.size.y
	for index in controls.size():
		for other in range(index + 1, controls.size()):
			complete = complete and not controls[index].get_global_rect().intersects(controls[other].get_global_rect())
	var view := menu._frame.get_node("field_of_view") as HSlider
	complete = complete and view.position.y + view.size.y <= control_area.position.y - 8.0
	complete = complete and menu._frame.get_node("invert_y").tooltip_text == L10n.text("Also reverses gamepad vertical aim.")
	_check(code + " five settings toggles translate, fit and stay clear of the sliders", complete)


func _small_settings_checks() -> void:
	var original_size := get_window().size
	var original_language := String(GameSettings.get_value("language"))
	var menu: FlightMenu = _main.menu
	get_window().size = Vector2i(800, 450)
	menu.show_settings()
	for code: String in L10n.language_codes():
		GameSettings.set_value("language", code, false)
		await _frames(3)
		_settings_controls_check(menu, code + " / 800x450")
		var usable := _inside_canvas(menu)
		for key: String in ["invert_y", "invert_roll"]:
			var check := menu._frame.get_node(key) as CheckButton
			usable = usable and check.get_theme_font_size("font_size") * menu._frame.scale.x >= 8.0
		_check(code + " inversion captions keep readable type at the minimum window size", usable)
	get_window().size = original_size
	GameSettings.set_value("language", original_language, false)
	await _frames(3)
	menu.go_back()


func _control_preference_checks() -> void:
	var menu: FlightMenu = _main.menu
	menu.show_settings()
	await _frames(3)
	_check("settings preserve their original sensitivity-slider first focus",
		get_viewport().gui_get_focus_owner() == menu._frame.get_node("mouse_sensitivity"))
	for key: String in ["invert_roll", "invert_y"]:
		var check := menu._frame.get_node(key) as CheckButton
		check.grab_focus()
		await _settings_key(KEY_SPACE)
		_check("keyboard toggles and saves " + key, check.button_pressed and GameSettings.get_value(key) == true \
			and GameSettings.last_save_error == OK)
	var focus := menu._frame.get_node("invert_roll") as CheckButton
	focus.grab_focus()
	GameSettings.set_value("language", "ar", false)
	await _frames(3)
	_check("switching language preserves inversion toggles and their focus", menu.page == "settings" \
		and get_viewport().gui_get_focus_owner() == menu._frame.get_node("invert_roll") \
		and menu._frame.get_node("invert_roll").button_pressed and menu._frame.get_node("invert_y").button_pressed)
	GameSettings.values = GameSettings.DEFAULTS.duplicate()
	GameSettings.load_preferences()
	menu.show_settings()
	await _frames(3)
	_check("inversion choices survive disk reload and rebuild the real controls", GameSettings.get_value("invert_roll") == true \
		and GameSettings.get_value("invert_y") == true and menu._frame.get_node("invert_roll").button_pressed \
		and menu._frame.get_node("invert_y").button_pressed)
	GameSettings.set_value("invert_roll", "yes", false)
	GameSettings.set_value("invert_y", 1, false)
	_check("non-boolean inversion preferences recover safely", GameSettings.get_value("invert_roll") == false \
		and GameSettings.get_value("invert_y") == false)
	GameSettings.reset_to_defaults(false)
	menu.show_settings()
	await _frames(2)
	_check("restoring defaults clears both inversion controls", not menu._frame.get_node("invert_roll").button_pressed \
		and not menu._frame.get_node("invert_y").button_pressed)
	menu.go_back()


func _settings_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _npc_selector_check(menu: FlightMenu, code: String) -> void:
	var fits := true
	for spec: Array in [["AllyCount", "ALLY NPCS", "ally_count"], ["EnemyCount", "ENEMY NPCS", "enemy_count"]]:
		var selector := menu._frame.get_node_or_null(spec[0]) as SpinBox
		if selector == null:
			fits = false
			continue
		fits = fits and selector.accessibility_name == L10n.text(spec[1]) \
			and selector.value == GameSettings.get_value(spec[2]) and selector.size.y <= 40.1
		var slot := Rect2(Vector2.ZERO, selector.size).grow(0.1)
		var field := selector.get_line_edit()
		fits = fits and slot.encloses(field.get_rect()) \
			and field.get_combined_minimum_size().y <= selector.size.y + 0.1
		for button_name: String in ["Decrease", "Increase"]:
			var button := selector.get_node_or_null(button_name) as Button
			fits = fits and button != null and slot.encloses(button.get_rect())
		var caption: Label
		for child: Node in menu._frame.get_children():
			if child is Label and child.get_meta("source_text", "") == spec[1]:
				caption = child
		fits = fits and caption != null and caption.text == L10n.text(spec[1]) \
			and caption.get_minimum_size().x <= caption.size.x + 0.1 \
			and caption.get_minimum_size().y <= caption.size.y + 0.1
	_check(code + " NPC selectors translate and fit their numeric control slots", fits)


func _wrapped_body_check(menu: FlightMenu, code: String, screen: String, minimum_labels: int) -> void:
	var labels: Array[Label] = []
	var first_lines: Array[int] = []
	for child: Node in menu._frame.get_children():
		if child is Label and child.autowrap_mode != TextServer.AUTOWRAP_OFF:
			labels.append(child)
			# Querying the count shapes the current text. Check it again after
			# further layout frames, rather than accepting a stale zero count.
			first_lines.append(child.get_line_count())
	await _frames(2)
	var complete := labels.size() >= minimum_labels
	var problems := ""
	for index in labels.size():
		var label := labels[index]
		var lines := label.get_line_count()
		if lines != first_lines[index] or not _wrapped_text_complete(label):
			complete = false
			problems += " [%s: %d/%d visible lines, %s, %dpx font]" % [
				String(label.get_meta("source_text", label.text)).replace("\n", " / "),
				label.get_visible_line_count(), lines, label.size,
				label.get_theme_font_size("font_size")]
	_check(code + " " + screen + " body text is fully visible after layout", complete, problems)


func _wrapped_text_complete(label: Label) -> bool:
	var lines := label.get_line_count()
	return label.is_visible_in_tree() and not label.text.is_empty() \
		and lines >= label.text.count("\n") + 1 \
		and label.get_visible_line_count() == lines \
		and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING \
		and label.lines_skipped == 0 and label.max_lines_visible == -1 \
		and label.visible_characters == -1


func _wrapped_guard_check(menu: FlightMenu) -> void:
	# Use a real translated results label to prove the visibility guard rejects
	# both vertical clipping and ellipsis, not just controls outside the canvas.
	var body: Label
	for child: Node in menu._frame.get_children():
		if child is Label and child.autowrap_mode != TextServer.AUTOWRAP_OFF:
			body = child
			break
	if body == null:
		_check("wrapped-text guard finds the real results body", false)
		return
	var original_size := body.size
	body.size = Vector2(original_size.x, 1)
	await _frames(2)
	var rejects_clipping := body.get_line_count() > 0 and not _wrapped_text_complete(body)
	body.size = original_size
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	await _frames(2)
	var rejects_ellipsis := not _wrapped_text_complete(body)
	body.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_check("wrapped-text guard detects hidden lines and ellipsis", rejects_clipping and rejects_ellipsis)


func _heading_check(menu: FlightMenu, code: String, screen: String, source: String, bounds: Rect2, next_source: String) -> void:
	var heading: Label
	var next_label: Label
	for child: Node in menu._frame.get_children():
		if not child is Label:
			continue
		if child.get_meta("source_text", "") == source:
			heading = child
		elif child.get_meta("source_text", "") == next_source:
			next_label = child
	if heading == null or next_label == null:
		_check(code + " " + screen + " heading and caption are present", false)
		return
	var first_lines := heading.get_line_count()
	var first_size := heading.size
	await _frames(2)
	var font := heading.get_theme_font("font")
	var font_size := heading.get_theme_font_size("font_size")
	var minimum := heading.get_minimum_size()
	var measured := font.get_multiline_string_size(heading.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# A non-wrapped Label can report every line visible by growing beyond its
	# assigned slot. Check the actual rectangle and minimum, then the caption
	# clearance, so enlarged fallback metrics cannot produce a false pass.
	var fits: bool = first_lines == heading.get_line_count() and first_lines >= 2 \
		and first_size.is_equal_approx(heading.size) \
		and heading.position.is_equal_approx(bounds.position) \
		and heading.size.x <= bounds.size.x + 0.1 and heading.size.y <= bounds.size.y + 0.1 \
		and minimum.y <= bounds.size.y + 0.1 and measured.x <= bounds.size.x + 0.1 \
		and heading.get_visible_line_count() == heading.get_line_count() \
		and heading.position.y + heading.size.y <= next_label.position.y - 20.0 \
		and font_size >= 30 and font is FontFile and not font.allow_system_fallback \
		and font.resource_path.begins_with("res://assets/fonts/") \
		and heading.text_direction == (Control.TEXT_DIRECTION_RTL if code == "ar" else Control.TEXT_DIRECTION_AUTO)
	_check(code + " " + screen + " heading fits its slot and clears the next caption", fits,
		"size %s, minimum %s, next label at %.0f, font %d" % [heading.size, minimum, next_label.position.y, font_size] if not fits else "")


func _inside_canvas(menu: FlightMenu) -> bool:
	for child: Node in menu._frame.get_children():
		if not child is Control:
			continue
		var control := child as Control
		if control.position.x < 0 or control.position.y < 0 \
				or control.position.x + control.size.x > menu.CANVAS.x + 1.0 \
				or control.position.y + control.size.y > menu.CANVAS.y + 1.0:
			print("    outside canvas: %s %s %s" % [control.name, control.position, control.size])
			return false
	return true


func _pause_checks() -> void:
	# This checks language switching, with a compact explicit fleet; the title
	# keeps the production default squadron selection.
	_main.ally_count = 2
	_main.enemy_count = 3
	_main._start_match(false)
	await _frames(3)
	_main._set_paused(true)
	_main.menu.show_settings()
	var clock := GameMatch.remaining
	var positions: Array[Vector3] = []
	for row: Dictionary in _main._roster:
		positions.append(row.ship.global_position)
	var options := _main.menu._frame.get_node("language") as OptionButton
	var arabic := L10n.language_codes().find("ar")
	options.select(arabic)
	options.item_selected.emit(arabic)
	await _frames(5)
	var stationary := true
	for index in positions.size():
		stationary = stationary and positions[index].is_equal_approx(_main._roster[index].ship.global_position)
	_check("choosing a language through the real selector keeps combat paused", get_tree().paused
		and _main.paused and GameMatch.remaining == clock and stationary and L10n.locale == "ar")
	_main.menu.go_back()
	_check("localized settings return to the pause screen", _main.menu.page == "pause" and _main.paused)
	_main._set_paused(false)
	_check("resuming after language selection keeps the same fleet", not get_tree().paused and _main._roster.size() == 6)
	_main._show_title()


func _preference_checks() -> void:
	GameSettings.set_value("language", "hi")
	GameSettings.values = GameSettings.DEFAULTS.duplicate()
	GameSettings.load_preferences()
	_check("the language preference survives save and reload", GameSettings.get_value("language") == "hi"
		and L10n.locale == "hi" and GameSettings.last_save_error == OK)
	GameSettings.set_value("language", "../unsupported", false)
	_check("unsupported locale values recover to English", GameSettings.get_value("language") == "en" and L10n.locale == "en")
	var malformed := ConfigFile.new()
	malformed.set_value("player", "language", 12)
	malformed.save(GameSettings.storage_path)
	GameSettings.load_preferences()
	_check("malformed saved language values recover safely", GameSettings.get_value("language") == "en" and L10n.locale == "en")
	GameSettings.set_value("language", "ko", false)
	GameSettings.reset_to_defaults(false)
	_check("restore defaults resets both settings and translation state", L10n.locale == "en" and GameSettings.get_value("language") == "en")


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


func _check(caption: String, ok: bool, detail := "") -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s %s" % ["PASS" if ok else "FAIL", caption, detail])
