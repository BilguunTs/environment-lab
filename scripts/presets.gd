## Named experiment presets.
## Each preset lists only what differs from the default scene state (the "Cold Dawn" mood
## authored in playground.tscn); anything omitted falls back to the default. Use the panel's
## "Copy settings" button to grab the current state as text and paste a new entry here.

const ALL := {
	# The Stage 2 look, kept as a "before" reference: flat light, one grey, nothing moves.
	"Flat Overcast": {
		"light_energy": 1.0,
		"light_elevation": 28.0,
		"light_azimuth": 150.0,
		"sun_color": Color(0.86, 0.9, 1.0),
		"ambient_energy": 0.5,
		"sky_color": Color(0.56, 0.6, 0.62),
		"zenith_color": Color(0.56, 0.6, 0.62),
		"sun_glow": 0.0,
		"light_shafts": false,
		"mist": 0.0,
		"wind": 0.0,
		"motes": false,
		"supernatural": false,
	},
	"Wide Reveal": {
		"view": "Reveal",
		"light_elevation": 22.0,
		"fog_density": 0.008,
		"fog_height_density": 0.04,
	},
	"Low Silhouette": {
		"view": "Gameplay",
		"cam_height": 0.7,
		"cam_distance": 5.0,
		"cam_pitch": 2.0,
		"cam_fov": 55.0,
		"light_energy": 2.6,
		"light_elevation": 6.0,
		"light_azimuth": 175.0,
		"sun_color": Color(1.0, 0.72, 0.45),
		"sky_color": Color(0.85, 0.72, 0.56),
		"zenith_color": Color(0.4, 0.43, 0.52),
		"sun_glow": 0.35,
		"fog_density": 0.014,
		"fog_height_density": 0.02,
		"mist": 0.1,
	},
	"Golden Backlight": {
		"view": "Forest Gate",
		"light_energy": 2.3,
		"light_elevation": 9.0,
		"light_azimuth": 172.0,
		"sun_color": Color(1.0, 0.7, 0.42),
		"ambient_energy": 0.28,
		"sky_color": Color(0.88, 0.72, 0.52),
		"zenith_color": Color(0.42, 0.47, 0.58),
		"sun_glow": 0.6,
		"shaft_density": 0.012,
	},
	"Foggy Forest": {
		"view": "Path Low",
		"light_energy": 1.4,
		"light_elevation": 35.0,
		"sun_color": Color(0.95, 0.9, 0.82),
		"ambient_energy": 0.45,
		"sky_color": Color(0.58, 0.6, 0.58),
		"zenith_color": Color(0.45, 0.5, 0.52),
		"sun_glow": 0.15,
		"fog_density": 0.026,
		"fog_height_density": 0.2,
		"shaft_density": 0.012,
		"mist": 0.6,
	},
	"Ritual Clearing": {
		"view": "Clearing",
		"light_energy": 0.5,
		"light_elevation": 4.0,
		"light_azimuth": 200.0,
		"sun_color": Color(1.0, 0.5, 0.35),
		"ambient_energy": 0.3,
		"sky_color": Color(0.32, 0.27, 0.32),
		"zenith_color": Color(0.1, 0.12, 0.18),
		"sun_glow": 0.5,
		"fog_density": 0.022,
		"fog_height_density": 0.15,
		"mist": 0.8,
		"spirit_amount": 0.8,
		"hole_glow": 1.0,
	},
	"Moonlit": {
		"light_energy": 0.45,
		"light_elevation": 38.0,
		"light_azimuth": 120.0,
		"sun_color": Color(0.62, 0.72, 1.0),
		"ambient_energy": 0.4,
		"sky_color": Color(0.13, 0.16, 0.21),
		"zenith_color": Color(0.04, 0.05, 0.09),
		"sun_glow": 0.1,
		"fog_density": 0.02,
		"shaft_density": 0.02,
		"mist": 0.7,
		"wind": 0.35,
		"spirit_amount": 0.9,
		"hole_glow": 1.2,
	},
	# Stage 7: dusk with the last light behind the monolith, so the cold hole glow and the
	# spirit stream carry the frame. The warm ember is the only other light source.
	"Awakened": {
		"view": "Clearing",
		"light_energy": 0.35,
		"light_elevation": 3.0,
		"light_azimuth": 172.0,
		"sun_color": Color(0.9, 0.55, 0.45),
		"ambient_energy": 0.25,
		"sky_color": Color(0.22, 0.24, 0.32),
		"zenith_color": Color(0.06, 0.08, 0.14),
		"sun_glow": 0.3,
		"fog_density": 0.016,
		"shaft_density": 0.014,
		"mist": 0.6,
		"spirit_amount": 1.0,
		"hole_glow": 1.4,
	},
}


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


## "" when the saved presets file reads fine or doesn't exist yet, otherwise a message for the
## panel's status line (all() silently shows only the built-ins in that case).
static func load_error(path := USER_PATH) -> String:
	var err := ConfigFile.new().load(path)
	if err == OK or err == ERR_FILE_NOT_FOUND:
		return ""
	return "Can't read %s (error %d): fix or delete it" % [path, err]


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
