
## Saved presets (plain text: edit by hand, delete a preset by deleting its section).
## res:// is read-only in exported builds; this playground is never exported.
const USER_PATH := "res://presets/user_presets.cfg"
## Names become ConfigFile section headers, so keep them to safe characters.
const NAME_PATTERN := "^[A-Za-z0-9 _\\-]+$"


## Built-in presets followed by the saved ones (built-in names win).
static func all(path := USER_PATH) -> Dictionary:
	var result := ALL.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return result
	for section in cfg.get_sections():
		if result.has(section):
			continue
		var preset := {}
		for key in cfg.get_section_keys(section):
			preset[key] = cfg.get_value(section, key)
		result[section] = preset
	return result


## The keys of `state` whose values differ from `base`, with the values from `state`.
static func overrides(state: Dictionary, base: Dictionary) -> Dictionary:
	var result := {}
	for key in state:
		if not base.has(key) or not same_value(state[key], base[key]):
			result[key] = state[key]
	return result


static func same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
		return is_equal_approx(float(a), float(b))
	if a is Color and b is Color:
		return a.is_equal_approx(b)
	return typeof(a) == typeof(b) and a == b


## Saves `state` as overrides on top of `default_state` (plus the view, since a preset is also
## a shot). Returns "" on success, otherwise a message for the panel's status line.
static func save_user(preset_name: String, state: Dictionary, default_state: Dictionary, path := USER_PATH) -> String:
	preset_name = preset_name.strip_edges()
	if preset_name.is_empty():
		return "Type a preset name first"
	if RegEx.create_from_string(NAME_PATTERN).search(preset_name) == null:
		return "Use letters, digits, spaces, - or _ in preset names"
	if ALL.has(preset_name) or preset_name == "Reset":
		return "Name taken by a built-in preset"
	var cfg := ConfigFile.new()
	var loaded := cfg.load(path)
	if loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		return "Can't read %s (error %d): fix or delete it first" % [path, loaded]
	if cfg.has_section(preset_name):
		cfg.erase_section(preset_name)
	var values := overrides(state, default_state)
	values["view"] = state.get("view", "Gameplay")
	for key in values:
		cfg.set_value(preset_name, key, values[key])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := cfg.save(path)
	return "" if err == OK else "Could not write %s (error %d)" % [path, err]
