class_name DevPanel
extends PanelContainer
## Runtime experimentation panel (toggle with F1). Every control is bound to a
## playground parameter key; `sync()` pulls values back after presets/resets.
## Controls never take keyboard focus (so WASD and hotkeys keep working), except the preset
## name field, which pauses them while you type.

const Presets := preload("res://scripts/presets.gd")
const ACCENT := Color(0.95, 0.68, 0.35)
const DIFF_LINES := 8  # longer diffs end in "+N more"

var _pg: Node
var _controls := {}  # key -> Control
var _value_labels := {}  # key -> Label (sliders only)
var _root: VBoxContainer  # holds every section
var _box: VBoxContainer  # the section currently being filled
var _status: Label
var _preset_grid: GridContainer
var _preset_name: LineEdit
var _diff_label: Label
var _diff_timer := 0.0


func setup(playground: Node) -> void:
	_pg = playground
	_build_frame()

	_section("Camera", false)
	_option("view", "View", _pg.view_names())
	_slider("cam_fov", "FOV", 10, 100, 1)
	_slider("cam_height", "Height", 0.2, 8, 0.1)
	_slider("cam_distance", "Distance", 1, 40, 0.5)
	_slider("cam_pitch", "Pitch", -10, 80, 1)
	_slider("cam_shift_x", "Shift X", -4, 4, 0.05)
	_slider("cam_shift_y", "Shift Y", -3, 3, 0.05)
	_note("Height, distance, pitch and shift drive the gameplay camera. Shift slides the frame without turning it, so the player can sit on a third.")
	var view_row := HBoxContainer.new()
	_box.add_child(view_row)
	view_row.add_child(_button("Scout (F)", _pg.set_param.bind("view", "Scout")))
	view_row.add_child(_button("Bookmark (B)", _pg.bookmark_view))

	_section("Framing & Values", false)
	_option("guides_grid", "Grid", PackedStringArray(CompositionGuides.GRIDS))
	_option("guides_aspect", "Aspect", PackedStringArray(CompositionGuides.ASPECTS.keys()))
	_check("guides_center", "Center marker")
	_option("value_mode", "Values", PackedStringArray(_pg.VALUE_MODES))
	_slider("value_split", "Value split", 0.05, 0.9, 0.01)
	_slider("value_squint", "Squint", 0, 6, 0.1)
	_note("Notan / 3-Value reduce the frame to big light and dark shapes; Squint blurs away detail. If the composition doesn't read here, more props won't fix it.")

	_section("Lighting")
	_slider("light_energy", "Sun energy", 0, 4, 0.05)
	_slider("light_elevation", "Sun height", 1, 88, 1)
	_slider("light_azimuth", "Sun angle", -180, 180, 1)
	_color("sun_color", "Sun colour")
	_slider("ambient_energy", "Shadow fill", 0, 1.5, 0.01)
	_check("shadows", "Shadows")
	_note("Shadow fill is sky light in the shadows (it takes the Sky top colour). Lower fill = deeper darks = more drama. A sun angle around 160-200 back-lights the landmark from the main views.")

	_section("Atmosphere")
	_color("sky_color", "Horizon / fog")
	_color("zenith_color", "Sky top")
	_slider("sun_glow", "Sun glow", 0, 1, 0.01)
	_check("fog_enabled", "Fog")
	_slider("fog_density", "Density", 0, 0.12, 0.001)
	_slider("fog_height_density", "Ground fog", 0, 1, 0.01)
	_check("light_shafts", "Light shafts (volumetric fog)")
	_slider("shaft_density", "Shaft density", 0, 0.08, 0.001)
	_slider("mist", "Drifting mist", 0, 2, 0.01)
	_note("Light shafts and mist are volumetric: mist only shows while Light shafts is on.")

	_section("Motion")
	_slider("wind", "Wind", 0, 2, 0.01)
	_slider("wind_direction", "Wind direction", 0, 360, 1)
	_check("motes", "Floating motes")
	_note("Wind drives grass, tree sway, cloth flutter, mist drift and motes. Direction is where it blows toward: 0 = into the screen from Gameplay's start, 90 = right. Fire and lantern always flicker.")

	_section("Supernatural")
	_check("supernatural", "Monolith awake (glow, shaft, spirits)")
	_slider("spirit_amount", "Spirits", 0, 1, 0.01)
	_slider("hole_glow", "Hole glow", 0, 2, 0.01)
	_note("Spirits flow from the hole to the ember. The cold shaft from the hole only shows while Light shafts is on.")

	_section("Environment")
	_check("landmark_visible", "Landmark")
	_check("props_visible", "Story props (camp, posts, cairns, stumps, log)")
	_check("grass_visible", "Grass")
	_option("forest_mode", "Forest", PackedStringArray(_pg.FOREST_MODES))
	_slider("scatter_seed", "Seed", 1, 999, 1)
	_slider("tree_density", "Tree density", 0, 10, 0.1)
	_slider("tree_spacing", "Tree spacing", 1.5, 8, 0.1)
	_slider("tree_clumping", "Clumping", 0, 1, 0.01)
	_slider("rock_density", "Rock density", 0, 4, 0.05)
	var scatter_row := HBoxContainer.new()
	_box.add_child(scatter_row)
	scatter_row.add_child(_button("New seed", _pg.new_seed))
	_check("show_zones", "Show exclusion zones")
	_note("Scatter sliders apply in Procedural mode. Same seed + same sliders = same forest. Zones, the path margin and hero items (gate trees, framing boulders, props) are always kept clear.")

	_section("Compare", false)
	var compare_row := HBoxContainer.new()
	_box.add_child(compare_row)
	compare_row.add_child(_button("Pin A (P)", _pg.compare.pin))
	compare_row.add_child(_button("Split (Z)", _pg.compare.toggle_split))
	compare_row.add_child(_button("Save pair", _pg.compare.save_pair))
	_diff_label = Label.new()
	_diff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_label.add_theme_font_size_override("font_size", 11)
	_box.add_child(_diff_label)
	_note("Pin A, change something, then hold X to see A or press Z for a split screen (drag the divider). A and B share the camera, guides and value view. In split view A re-renders when the camera stops (a short blink).")

	_section("Presets")
	_preset_grid = GridContainer.new()
	_preset_grid.columns = 2
	_box.add_child(_preset_grid)
	refresh_presets()
	var save_row := HBoxContainer.new()
	_box.add_child(save_row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Preset name"
	_preset_name.size_flags_horizontal = SIZE_EXPAND_FILL
	_preset_name.focus_entered.connect(_pg.set_typing.bind(true))
	_preset_name.focus_exited.connect(_pg.set_typing.bind(false))
	_preset_name.text_submitted.connect(func(_text: String) -> void: _save_preset())
	save_row.add_child(_preset_name)
	save_row.add_child(_button("Save preset", _save_preset))
	_note("Saves what differs from the default (plus the view) to presets/user_presets.cfg. Same name overwrites; delete one by editing that file.")

	_section("Capture", false)
	var row := HBoxContainer.new()
	_box.add_child(row)
	row.add_child(_button("Screenshot", _pg.take_screenshot))
	row.add_child(_button("All views", _pg.capture_all_views))
	row.add_child(_button("Copy settings", _pg.copy_state_to_clipboard))

	_section("Debug", false)
	_option("debug_draw", "Render", PackedStringArray(_pg.DEBUG_DRAWS.keys()))
	_check("probe", "Value probe (cursor value, p5/p50/p95, histogram)")
	_check("perf_hud", "Perf readout (fps, CPU/GPU ms, draw calls)")
	_check("light_gizmos", "Light gizmos (ranges, cones, sun direction)")
	_note("Unshaded = palette and values without light; Lighting = light without palette. Overdraw shows where fog, particles and foliage stack up. Debug views are not part of presets or A/B.")

	_box = _root
	_status = Label.new()
	_status.add_theme_color_override("font_color", ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)
	_note("WASD move · Shift sprint · RMB drag / Q E orbit · Wheel zoom
C views · F scout · B bookmark · G grid · V values
P pin A · X hold A · Z split · F2 render mode
F12 screenshot · F1 panel")

	sync()


func sync() -> void:
	for key in _controls:
		var c: Control = _controls[key]
		var value = _pg.get_param(key)
		if c is OptionButton:
			for i in c.item_count:
				if c.get_item_text(i) == value:
					c.select(i)
		elif c is ColorPickerButton:
			c.color = value
		elif c is CheckBox:
			c.set_pressed_no_signal(value)
		elif c is HSlider:
			c.set_value_no_signal(value)
			_value_labels[key].text = _label_for(key, value, c.step)


func notify(text: String) -> void:
	if _status:
		_status.text = text


func status_text() -> String:
	return _status.text if _status else ""


## Lists what differs between A and B (the experiment log's "Changed" column).
func update_compare() -> void:
	if _diff_label == null:
		return
	var c: Compare = _pg.compare
	if not c.has_a():
		_diff_label.text = "Nothing pinned."
		return
	var lines := c.diff()
	if lines.is_empty():
		_diff_label.text = "A = B (nothing changed yet)"
		return
	var text := "\n".join(PackedStringArray(lines.slice(0, DIFF_LINES)))
	if lines.size() > DIFF_LINES:
		text += "\n+%d more" % (lines.size() - DIFF_LINES)
	_diff_label.text = text


func _process(delta: float) -> void:
	_diff_timer += delta
	if _diff_timer >= 0.25:  # sliders don't call sync(), so refresh the diff a few times a second
		_diff_timer = 0.0
		update_compare()


# --- Builders -----------------------------------------------------------------

func _build_frame() -> void:
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 12
	offset_top = 12
	offset_right = 352
	offset_bottom = -12
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.06, 0.86)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 4)
	scroll.add_child(_root)
	_box = _root


## Starts a collapsible section; following controls go into it.
func _section(title: String, open := true) -> void:
	if _root.get_child_count() > 0:
		_root.add_child(HSeparator.new())
	var header := Button.new()
	header.flat = true
	header.focus_mode = FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_color_override("font_color", ACCENT)
	header.add_theme_color_override("font_hover_color", ACCENT.lightened(0.3))
	header.add_theme_font_size_override("font_size", 13)
	_root.add_child(header)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.visible = open
	_root.add_child(content)
	var label := title.to_upper()
	header.text = ("▾ " if open else "▸ ") + label
	header.pressed.connect(func() -> void:
		content.visible = not content.visible
		header.text = ("▾ " if content.visible else "▸ ") + label)
	_box = content


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	label.add_theme_font_size_override("font_size", 11)
	_box.add_child(label)


func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 84
	row.add_child(label)
	_box.add_child(row)
	return row


func _slider(key: String, text: String, min_v: float, max_v: float, step: float) -> void:
	var row := _row(text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.focus_mode = FOCUS_NONE
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 66
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(slider)
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		_pg.set_param(key, v)
		value_label.text = _label_for(key, v, step))
	_controls[key] = slider
	_value_labels[key] = value_label


func _check(key: String, text: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.focus_mode = FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: _pg.set_param(key, on))
	_box.add_child(check)
	_controls[key] = check


func _color(key: String, text: String) -> void:
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.focus_mode = FOCUS_NONE
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	picker.custom_minimum_size.y = 24
	picker.color_changed.connect(func(c: Color) -> void: _pg.set_param(key, c))
	_row(text).add_child(picker)
	_controls[key] = picker


func _option(key: String, text: String, items: PackedStringArray) -> void:
	var option := OptionButton.new()
	option.focus_mode = FOCUS_NONE
	option.size_flags_horizontal = SIZE_EXPAND_FILL
	for item in items:
		option.add_item(item)
	option.item_selected.connect(func(i: int) -> void:
		_pg.set_param(key, option.get_item_text(i))
		sync())  # e.g. the FOV slider follows the newly active camera
	_row(text).add_child(option)
	_controls[key] = option


## Rebuilds the view list after a bookmark adds a camera.
func refresh_views() -> void:
	var option: OptionButton = _controls["view"]
	option.clear()
	for item in _pg.view_names():
		option.add_item(item)
	sync()


## Rebuilds the preset buttons, e.g. after a save adds one.
func refresh_presets() -> void:
	for child in _preset_grid.get_children():
		_preset_grid.remove_child(child)
		child.queue_free()
	for preset_name in Presets.all(_pg.preset_path):
		_preset_grid.add_child(_button(preset_name, _pg.apply_preset.bind(preset_name)))
	_preset_grid.add_child(_button("Reset", _pg.reset_scene))
	var problem := Presets.load_error(_pg.preset_path)
	if problem != "":
		notify(problem)


func preset_buttons() -> PackedStringArray:
	var names := PackedStringArray()
	for child in _preset_grid.get_children():
		names.append(child.text)
	return names


func _save_preset() -> void:
	if _pg.save_preset(_preset_name.text):
		_preset_name.text = ""
	_preset_name.release_focus()


## A click anywhere outside the name field ends typing (Godot keeps focus otherwise).
func _input(event: InputEvent) -> void:
	if _preset_name and _preset_name.has_focus() and event is InputEventMouseButton and event.pressed \
			and not _preset_name.get_global_rect().has_point(event.position):
		_preset_name.release_focus()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		action.call()
		sync())
	return button


## FOV also shows its full-frame lens equivalent: easier to reason about than degrees.
func _label_for(key: String, value: float, step: float) -> String:
	if key == "cam_fov":
		return "%d° %dmm" % [roundi(value), roundi(_pg.focal_length_mm(value))]
	return _fmt(value, step)


static func _fmt(value: float, step: float) -> String:
	if step >= 1.0:
		return str(roundi(value))
	if step >= 0.01:
		return "%.2f" % value
	return "%.3f" % value
