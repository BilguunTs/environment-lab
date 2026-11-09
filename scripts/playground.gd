extends Node3D
## Root of the playground. Owns every tunable scene parameter behind a single
## get_param/set_param interface so the dev panel, presets and screenshots all
## talk to the scene the same way.
##
## Command line (after `--`): --preset="Name"  --capture-views  --quit

const Presets := preload("res://scripts/presets.gd")
const SCREENSHOT_DIR := "res://screenshots"
const VALUE_MODES := ["Color", "Grayscale", "3-Value", "Notan"]
const FOREST_MODES := ["Manual", "Procedural"]
## Debug views change how you look at the scene, not the scene: they're kept out of
## PARAM_ORDER, so presets, Copy settings and A/B ignore them.
const DEBUG_DRAWS := {
	"Normal": Viewport.DEBUG_DRAW_DISABLED,
	"Unshaded": Viewport.DEBUG_DRAW_UNSHADED,
	"Lighting": Viewport.DEBUG_DRAW_LIGHTING,
	"Overdraw": Viewport.DEBUG_DRAW_OVERDRAW,
	"Wireframe": Viewport.DEBUG_DRAW_WIREFRAME,
}
const GAMEPLAY := 0
const SCOUT := 1
const GAMEPLAY_INTENT := "Follow camera. Use Shift X/Y to put the player on a third instead of dead centre."
const SCOUT_INTENT := "Scout: fly around (WASD, RMB look, Q/E down/up). Press B to bookmark the shot."
const MIST_DRIFT := 0.05  # noise-space units per second at wind 1.0
const MOTE_DRIFT := 0.3  # m/s² of sideways push on motes at wind 1.0
## Sky halo brightness relative to the in-fog sun scatter, so one slider drives both.
const SKY_GLOW_PER_SCATTER := 3.2

## Applied in this order: the view must switch before FOV is set on it.
const PARAM_ORDER := [
	"view", "cam_fov", "cam_height", "cam_distance", "cam_pitch", "cam_shift_x", "cam_shift_y",
	"guides_grid", "guides_center", "guides_aspect",
	"value_mode", "value_squint", "value_split",
	"light_energy", "light_elevation", "light_azimuth", "sun_color", "ambient_energy", "shadows",
	"sky_color", "zenith_color", "sun_glow", "fog_enabled", "fog_density", "fog_height_density",
	"light_shafts", "shaft_density", "mist",
	"wind", "wind_direction", "motes",
	"supernatural", "spirit_amount", "hole_glow",
	"landmark_visible", "props_visible", "grass_visible",
	"forest_mode", "scatter_seed", "tree_density", "tree_spacing", "tree_clumping", "rock_density", "show_zones",
]

## [0] gameplay, [1] scout, then authored viewpoints, then runtime bookmarks.
var _cameras: Array[Camera3D] = []
var _default_fovs: Array[float] = []
var _view := GAMEPLAY
var _last_fixed_view := GAMEPLAY  # where F returns to after scouting
var _bookmark_count := 0
var _default_state: Dictionary
var _player_start: Transform3D
var _layout_env: Environment  # fog-free copy for viewpoints with ignore_fog
var _hud: Label
var _mist_offset := Vector3.ZERO
var _forest_mode := "Manual"
var _show_zones := false
## Where user presets are saved; tests point this at user://.
var preset_path := Presets.USER_PATH
var _typing := false  # a panel text field has focus: no hotkeys, no walking
var compare: Compare
var probe: ValueProbe
var perf_hud: PerfHud
var light_gizmos: LightGizmos
var _overlay_restore := {}  # CanvasItem -> visible, while a capture hides the overlays
var _overlay_depth := 0  # nested hide_overlays() calls; only the outermost pair acts

@onready var player: Player = $Player
@onready var follow_cam: FollowCamera = $GameplayCamera
@onready var scout_cam: ScoutCamera = $ScoutCamera
@onready var sun: DirectionalLight3D = $Sun
@onready var env: Environment = $WorldEnvironment.environment
@onready var landmark: Node3D = $Landmark
@onready var props: Node3D = $Props
@onready var grass: GrassField = $Grass
@onready var mist: FogVolume = $Mist
@onready var wind: Wind = $Wind
@onready var motes: GPUParticles3D = $Player/Motes
@onready var spirit_stream: SpiritStream = $SpiritStream
@onready var hole_glow: Breathe = $Landmark/HoleGlow
@onready var hole_light: SpotLight3D = $Landmark/HoleLight
@onready var sky_material: ShaderMaterial = env.sky.sky_material
## The hand-placed forest. Detached from the tree (not just hidden) in procedural mode, so its
## colliders go away too.
@onready var manual_forest: Node3D = $Forest
@onready var tree_scatter: Scatter = $Scatter/Trees
@onready var rock_scatter: Scatter = $Scatter/Rocks
@onready var value_view: ColorRect = $UI/ValueView
@onready var guides: CompositionGuides = $UI/Guides
@onready var panel: DevPanel = $UI/DevPanel


func _ready() -> void:
	_sync_layout_env()
	_cameras.append(follow_cam)
	_cameras.append(scout_cam)
	for c in $Viewpoints.get_children():
		if c is Camera3D:
			_register_viewpoint(c)
	for c in _cameras:
		_default_fovs.append(c.fov)
	_player_start = player.global_transform
	# Unset shader uniforms read back as null, so give the value view explicit defaults.
	_value_material().set_shader_parameter("mode", 0)
	_value_material().set_shader_parameter("squint", 0.0)
	_value_material().set_shader_parameter("split", 0.62)
	_update_mote_gravity()
	_build_hud()
	panel.add_to_group("overlay")
	_hud.add_to_group("overlay")
	compare = Compare.new()
	compare.name = "Compare"
	compare.pg = self
	add_child(compare)
	compare.changed.connect(_on_compare_changed)
	compare.attach_view($UI, panel)
	probe = ValueProbe.new()
	probe.pg = self
	$UI.add_child(probe)
	perf_hud = PerfHud.new()
	perf_hud.pg = self
	$UI.add_child(perf_hud)
	light_gizmos = LightGizmos.new()
	light_gizmos.pg = self
	add_child(light_gizmos)
	_set_view(GAMEPLAY)
	_default_state = get_state()
	panel.setup(self)
	follow_cam.user_adjusted.connect(panel.sync)
	tree_scatter.generated.connect(_on_scatter_generated)
	rock_scatter.generated.connect(_on_scatter_generated)
	_run_command_line.call_deferred()


func _process(delta: float) -> void:
	# Advance the mist with the wind; integrating (instead of TIME * speed in the shader)
	# keeps it from jumping when the wind slider moves.
	var drift := wind.vector() * wind.strength * MIST_DRIFT * delta
	_mist_offset -= Vector3(drift.x, 0.0, drift.y)
	mist.material.set_shader_parameter("offset", _mist_offset)


func _exit_tree() -> void:
	if manual_forest and not manual_forest.is_inside_tree():
		manual_forest.free()  # detached in procedural mode; free it ourselves


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	if event.keycode == KEY_X:
		if not event.pressed or not _typing:  # a release always gets through, or A would stick
			compare.show_a(event.pressed)  # hold to see A
		return
	if _typing or compare.busy or not event.pressed:  # no hotkeys while typing or mid-capture
		return
	match event.keycode:
		KEY_F1:
			panel.visible = not panel.visible
		KEY_C:
			_cycle_view()
		KEY_F:
			_set_view(_last_fixed_view if _view == SCOUT else SCOUT)
		KEY_B:
			bookmark_view()
		KEY_G:
			guides.cycle_grid()
		KEY_V:
			set_param("value_mode", VALUE_MODES[(VALUE_MODES.find(get_param("value_mode")) + 1) % VALUE_MODES.size()])
		KEY_P:
			compare.pin()
		KEY_Z:
			compare.toggle_split()
		KEY_F2:
			var modes := DEBUG_DRAWS.keys()
			set_param("debug_draw", modes[(modes.find(get_param("debug_draw")) + 1) % modes.size()])
		KEY_F12:
			take_screenshot()
		_:
			return
	panel.sync()


# --- Parameters -------------------------------------------------------------

func view_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in _cameras.size():
		names.append("Gameplay" if i == GAMEPLAY else "Scout" if i == SCOUT else String(_cameras[i].name))
	return names


func get_param(key: String) -> Variant:
	match key:
		"view": return view_names()[_view]
		"cam_fov": return _cameras[_view].fov
		"cam_height": return follow_cam.height
		"cam_distance": return follow_cam.distance
		"cam_pitch": return follow_cam.pitch_deg
		"cam_shift_x": return follow_cam.h_offset
		"cam_shift_y": return follow_cam.v_offset
		"guides_grid": return guides.grid
		"guides_center": return guides.show_center
		"guides_aspect": return guides.aspect
		"value_mode": return VALUE_MODES[_value_material().get_shader_parameter("mode")]
		"value_squint": return _value_material().get_shader_parameter("squint")
		"value_split": return _value_material().get_shader_parameter("split")
		"light_energy": return sun.light_energy
		"light_elevation": return -sun.rotation_degrees.x
		"light_azimuth": return sun.rotation_degrees.y
		"sun_color": return sun.light_color
		"ambient_energy": return env.ambient_light_energy
		"shadows": return sun.shadow_enabled
		"sky_color": return env.fog_light_color
		"zenith_color": return env.ambient_light_color
		"sun_glow": return env.fog_sun_scatter
		"light_shafts": return env.volumetric_fog_enabled
		"shaft_density": return env.volumetric_fog_density
		"mist": return mist.material.get_shader_parameter("density")
		"wind": return wind.strength
		"wind_direction": return wind.direction_degrees
		"motes": return motes.emitting
		"supernatural": return spirit_stream.visible
		"spirit_amount": return spirit_stream.amount_ratio
		"hole_glow": return hole_glow.intensity
		"fog_enabled": return env.fog_enabled
		"fog_density": return env.fog_density
		"fog_height_density": return env.fog_height_density
		"landmark_visible": return landmark.visible
		"props_visible": return props.visible
		"grass_visible": return grass.visible
		"forest_mode": return _forest_mode
		"scatter_seed": return float(tree_scatter.random_seed)
		"tree_density": return tree_scatter.density
		"tree_spacing": return tree_scatter.min_spacing
		"tree_clumping": return tree_scatter.clumping
		"rock_density": return rock_scatter.density
		"show_zones": return _show_zones
		"probe": return probe.visible
		"perf_hud": return perf_hud.visible
		"light_gizmos": return light_gizmos.visible
		"debug_draw": return DEBUG_DRAWS.find_key(get_viewport().debug_draw)
	push_error("Unknown param: %s" % key)
	return null


func set_param(key: String, value: Variant) -> void:
	match key:
		"view": _set_view(maxi(0, view_names().find(value)))
		"cam_fov":
			_cameras[_view].fov = value
			_update_hud()
		"cam_height": follow_cam.height = value
		"cam_distance": follow_cam.distance = value
		"cam_pitch": follow_cam.pitch_deg = value
		"cam_shift_x": follow_cam.h_offset = value
		"cam_shift_y": follow_cam.v_offset = value
		"guides_grid": guides.grid = value
		"guides_center": guides.show_center = value
		"guides_aspect": guides.aspect = value
		"value_mode":
			_value_material().set_shader_parameter("mode", maxi(0, VALUE_MODES.find(value)))
			_update_value_view()
		"value_squint":
			_value_material().set_shader_parameter("squint", value)
			_update_value_view()
		"value_split": _value_material().set_shader_parameter("split", value)
		"light_energy": sun.light_energy = value
		"light_elevation": sun.rotation_degrees.x = -value
		"light_azimuth": sun.rotation_degrees.y = value
		"sun_color": sun.light_color = value
		"ambient_energy":
			env.ambient_light_energy = value
			_sync_layout_env()
		"shadows": sun.shadow_enabled = value
		"sky_color":
			# Horizon and fog share one colour: distant forms fade into the sky behind
			# them, which is what sells atmospheric perspective.
			env.background_color = value
			env.fog_light_color = value
			sky_material.set_shader_parameter("horizon_color", value)
			_sync_layout_env()
		"zenith_color":
			# Shadows are lit by the sky above them, so the ambient fill takes the zenith
			# colour: cool sky fill against a warm sun is the temperature contrast.
			sky_material.set_shader_parameter("zenith_color", value)
			env.ambient_light_color = value
			_sync_layout_env()
		"sun_glow":
			env.fog_sun_scatter = value
			sky_material.set_shader_parameter("glow_energy", value * SKY_GLOW_PER_SCATTER)
		"light_shafts": env.volumetric_fog_enabled = value
		"shaft_density": env.volumetric_fog_density = value
		"mist": mist.material.set_shader_parameter("density", value)
		"wind":
			wind.strength = value
			_update_mote_gravity()
		"wind_direction":
			wind.direction_degrees = value
			_update_mote_gravity()
		"motes":
			motes.emitting = value
			motes.visible = value
		"supernatural":
			# Off means the plain Stage 6 world: the hole shows sky again.
			spirit_stream.emitting = value
			spirit_stream.visible = value
			hole_glow.visible = value
			hole_light.visible = value
		"spirit_amount": spirit_stream.amount_ratio = value
		"hole_glow": hole_glow.intensity = value
		"fog_enabled": env.fog_enabled = value
		"fog_density": env.fog_density = value
		"fog_height_density": env.fog_height_density = value
		"landmark_visible": landmark.visible = value
		"props_visible": props.visible = value
		"grass_visible": grass.visible = value
		"forest_mode": _set_forest_mode(value)
		"scatter_seed":
			tree_scatter.random_seed = int(value)
			rock_scatter.random_seed = int(value)
		"tree_density": tree_scatter.density = value
		"tree_spacing": tree_scatter.min_spacing = value
		"tree_clumping": tree_scatter.clumping = value
		"rock_density": rock_scatter.density = value
		"show_zones":
			_show_zones = value
			for zone in $Scatter/Zones.get_children():
				zone.set_debug_visible(value)
		"probe": probe.visible = value
		"perf_hud": perf_hud.visible = value
		"light_gizmos": light_gizmos.visible = value
		"debug_draw": get_viewport().debug_draw = DEBUG_DRAWS.get(value, Viewport.DEBUG_DRAW_DISABLED)
		_: push_error("Unknown param: %s" % key)
	if key.begins_with("value_") and compare:
		compare.request_recapture()  # the value view is baked into the frozen A image


func get_state() -> Dictionary:
	var state := {}
	for key in PARAM_ORDER:
		state[key] = get_param(key)
	return state


## Applies the keys of `state`, skipping a value whose type differs from the default's (int and
## float count as one). Returns the skip notes, which are also shown in the panel's status line.
func apply_state(state: Dictionary) -> Array[String]:
	var skipped: Array[String] = []
	for key in PARAM_ORDER:
		if not state.has(key):
			continue
		if _default_state.has(key) and not _same_type(state[key], _default_state[key]):
			skipped.append("Skipped %s: expected %s" % [key, type_string(typeof(_default_state[key]))])
			continue
		set_param(key, state[key])
	panel.sync()
	if not skipped.is_empty():
		panel.notify("; ".join(PackedStringArray(skipped)))
	return skipped


static func _same_type(a: Variant, b: Variant) -> bool:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	return typeof(a) == typeof(b) or (typeof(a) in numeric and typeof(b) in numeric)


## Presets are layered on top of the default state, so they are always reproducible.
func apply_preset(preset_name: String) -> void:
	var presets := Presets.all(preset_path)
	if not presets.has(preset_name):
		panel.notify("No preset named %s" % preset_name)
		return
	_restore_fovs()
	var preset: Dictionary = presets[preset_name]
	var state := _default_state.duplicate()
	if preset.has("view") and not preset.has("cam_fov"):
		state.erase("cam_fov")  # keep the viewpoint's authored lens, not the gameplay FOV
	state.merge(preset, true)
	var skipped := apply_state(state)
	var note := "Preset: %s" % preset_name
	if not skipped.is_empty():
		note += " (%s)" % "; ".join(PackedStringArray(skipped))
	panel.notify(note)


## Saves the current state as a user preset (overrides on top of the default). True on success.
func save_preset(preset_name: String) -> bool:
	var error := Presets.save_user(preset_name, get_state(), _default_state, preset_path)
	if error != "":
		panel.notify(error)
		return false
	panel.refresh_presets()
	panel.notify("Saved preset: %s" % preset_name.strip_edges())
	return true


## While a panel text field has focus, keys type text instead of moving the player.
func set_typing(on: bool) -> void:
	_typing = on
	player.input_enabled = not on and _view != SCOUT
	follow_cam.input_enabled = not on
	scout_cam.input_enabled = not on
	if on and compare:
		compare.show_a(false)  # a held X can't be released while typing, and a save would store A


## Snaps the smoothed gameplay camera to its goal, so an applied state is seen at once
## (cam_height and the like would otherwise glide in over most of a second).
func settle_camera() -> void:
	follow_cam.snap()


func in_scout() -> bool:
	return _view == SCOUT


func _on_compare_changed() -> void:
	_update_hud()
	panel.update_compare()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and compare:
		compare.show_a(false)  # a held X never gets its key release once focus is gone


func reset_scene() -> void:
	_restore_fovs()
	player.global_transform = _player_start
	player.velocity = Vector3.ZERO
	follow_cam.yaw_deg = 0.0
	apply_state(_default_state)
	follow_cam.snap()
	panel.notify("Reset to default")


func copy_state_to_clipboard() -> void:
	var text := var_to_str(get_state())
	DisplayServer.clipboard_set(text)
	print(text)
	panel.notify("Settings copied to clipboard")


# --- Views ----------------------------------------------------------------------

## Freezes the current shot as a new viewpoint for this session and copies a .tscn
## snippet to the clipboard; paste it under the Viewpoints node to keep it.
func bookmark_view() -> void:
	var src := _cameras[_view]
	_bookmark_count += 1
	var vp := Viewpoint.new()
	vp.name = "Bookmark %d" % _bookmark_count
	vp.intent = "Bookmarked from %s. Write down what this shot is for." % view_names()[_view]
	vp.far = src.far
	$Viewpoints.add_child(vp)
	vp.global_transform = src.global_transform
	vp.fov = src.fov
	vp.h_offset = src.h_offset
	vp.v_offset = src.v_offset
	_register_viewpoint(vp)
	_default_fovs.append(vp.fov)

	var snippet := "[node name=\"%s\" type=\"Camera3D\" parent=\"Viewpoints\"]\ntransform = %s\nfov = %s\nfar = %s\n" % [
		vp.name, var_to_str(vp.transform), vp.fov, vp.far]
	DisplayServer.clipboard_set(snippet)
	print(snippet)
	panel.refresh_views()
	_set_view(_cameras.size() - 1)
	panel.notify("%s added (scene snippet copied to clipboard)" % vp.name)


func new_seed() -> void:
	set_param("scatter_seed", float(randi_range(1, 999)))
	panel.sync()


## Manual = the hand-placed Stage 1-4 forest. Procedural = the scatter layers.
## Hero items (gate trees, framing boulders), props and the landmark exist in both.
func _set_forest_mode(mode: String) -> void:
	_forest_mode = mode if mode in FOREST_MODES else "Manual"
	var procedural := _forest_mode == "Procedural"
	if procedural and manual_forest.is_inside_tree():
		remove_child(manual_forest)
	elif not procedural and not manual_forest.is_inside_tree():
		add_child(manual_forest)
	tree_scatter.visible = procedural
	rock_scatter.visible = procedural


func _on_scatter_generated(_count: int) -> void:
	if _forest_mode == "Procedural":
		panel.notify("Procedural forest: %d trees, %d rocks (seed %d)" % [tree_scatter.count, rock_scatter.count, tree_scatter.random_seed])


func _register_viewpoint(c: Camera3D) -> void:
	_cameras.append(c)
	if c.get("ignore_fog"):
		c.environment = _layout_env


func _cycle_view() -> void:
	var next := (_view + 1) % _cameras.size()
	if next == SCOUT:
		next += 1
	_set_view(next % _cameras.size())


func _set_view(index: int) -> void:
	if index == SCOUT and compare:
		compare.leave()  # Scout has its own camera; A/B needs one fixed shot
	if index == SCOUT and _view != SCOUT:
		scout_cam.start_from(_cameras[_view])
	if index != SCOUT:
		_last_fixed_view = index
	_view = index
	_cameras[index].make_current()
	player.input_enabled = index != SCOUT and not _typing
	if index == GAMEPLAY:
		follow_cam.snap()
	_update_hud()


func _update_mote_gravity() -> void:
	var push := wind.vector() * wind.strength * MOTE_DRIFT
	var process: ParticleProcessMaterial = motes.process_material
	process.gravity = Vector3(push.x, -0.03, push.y)


func _sync_layout_env() -> void:
	if _layout_env == null:
		_layout_env = env.duplicate()  # shares the sky resource, so sky colours follow
		_layout_env.fog_enabled = false
		_layout_env.volumetric_fog_enabled = false
	# Plan view: readability over mood, so fill the shadows with the (lighter) horizon colour.
	_layout_env.ambient_light_color = env.fog_light_color
	_layout_env.ambient_light_energy = maxf(env.ambient_light_energy, 1.0)


func _restore_fovs() -> void:
	for i in _cameras.size():
		_cameras[i].fov = _default_fovs[i]


## Full-frame (36x24 mm) focal length equivalent of a vertical field of view.
static func focal_length_mm(vertical_fov: float) -> float:
	return 12.0 / tan(deg_to_rad(vertical_fov) * 0.5)


# --- Value view & HUD -------------------------------------------------------------

func _value_material() -> ShaderMaterial:
	return value_view.material


func _update_value_view() -> void:
	# Only pay for the full-screen pass when it does something.
	value_view.visible = get_param("value_mode") != "Color" or get_param("value_squint") > 0.0


func _build_hud() -> void:
	_hud = Label.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud.offset_left = -440
	_hud.offset_right = -16
	_hud.offset_top = 12
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_font_size_override("font_size", 13)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 4)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(_hud)


func _update_hud() -> void:
	if _hud == null:
		return
	var cam := _cameras[_view]
	var intent := GAMEPLAY_INTENT
	if _view == SCOUT:
		intent = SCOUT_INTENT
	elif _view != GAMEPLAY:
		intent = cam.get("intent") if cam is Viewpoint else ""  # pasted bookmarks are plain cameras
	var tag: String = compare.hud_tag() if compare else ""
	_hud.text = "%s   %d°  ≈ %d mm%s\n%s" % [view_names()[_view].to_upper(), roundi(cam.fov), roundi(focal_length_mm(cam.fov)),
		("   ·   " + tag) if tag != "" else "", intent]


# --- Screenshots --------------------------------------------------------------

## Saves the current frame without the overlays (guides and value view stay, since they are
## part of the experiment). Returns the absolute file path.
func take_screenshot(label := "shot") -> String:
	hide_overlays()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	restore_overlays()
	var path := screenshot_path(label)
	image.save_png(path)
	panel.notify("Saved %s" % path.get_file())
	print("Screenshot: ", path)
	return path


## Absolute path for a new capture in screenshots/ (created, and kept out of Godot's importer).
func screenshot_path(label: String) -> String:
	var dir := ProjectSettings.globalize_path(SCREENSHOT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir.path_join(".gdignore")):
		FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE)  # keep Godot from importing shots
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	return dir.path_join("%s_%s.png" % [stamp, label.to_snake_case()])


## Hides everything in the "overlay" group (panel, HUD, compare view, probe, perf readout)
## for a clean capture; restore_overlays() puts each back as it was.
func hide_overlays() -> void:
	_overlay_depth += 1
	if _overlay_depth > 1:
		return
	for node in get_tree().get_nodes_in_group("overlay"):
		_overlay_restore[node] = node.visible
		node.visible = false


func restore_overlays() -> void:
	_overlay_depth = maxi(_overlay_depth - 1, 0)
	if _overlay_depth > 0:
		return
	for node in _overlay_restore:
		if is_instance_valid(node):
			node.visible = _overlay_restore[node]
	_overlay_restore.clear()


## Renders every fixed view (not Scout) with the current settings, for side-by-side comparison.
func capture_all_views() -> void:
	var previous := _view
	for i in _cameras.size():
		if i == SCOUT:
			continue
		_set_view(i)
		for _f in 3:
			await get_tree().process_frame
		await take_screenshot(view_names()[i])
	_set_view(previous)
	panel.sync()


func _run_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--preset="):
			apply_preset(arg.trim_prefix("--preset=").trim_prefix("\"").trim_suffix("\""))
	if "--capture-views" in args:
		for _f in 30:  # let shadows/SSAO settle
			await get_tree().process_frame
		await capture_all_views()
	if "--profile-views" in args:
		for _f in 30:
			await get_tree().process_frame
		await profile_views()
	if "--quit" in args:
		get_tree().quit()


## Measures every fixed view with grass on then off (settle 30 frames, measure 120), prints the
## table and writes it to screenshots/profile_<datetime>.md. Run with --disable-vsync.
func profile_views() -> String:
	var previous := _view
	var grass_was := grass.visible
	hide_overlays()
	var rows: Array[Dictionary] = []
	for i in _cameras.size():
		if i == SCOUT:
			continue
		_set_view(i)
		for on in [true, false]:
			grass.visible = on
			for _f in 30:
				await get_tree().process_frame
			var m: Dictionary = await perf_hud.measure(120)
			m["view"] = view_names()[i]
			m["grass"] = on
			rows.append(m)
	grass.visible = grass_was
	restore_overlays()
	_set_view(previous)
	panel.sync()
	var text := PerfHud.table(rows)
	print(text)
	var dir := screenshot_path("profile").get_base_dir()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(dir.path_join("profile_%s.md" % stamp), FileAccess.WRITE)
	if file:
		file.store_string(text)
	return text
