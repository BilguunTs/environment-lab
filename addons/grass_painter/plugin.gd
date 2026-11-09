@tool
extends EditorPlugin
## Grass mask painter: select a GrassField and paint its density / height mask in the 3D
## viewport. LMB paints, Shift + LMB erases, [ and ] shrink / grow the brush. One stroke is one
## undo step; the mask is saved to its own .res file at the end of every stroke.
##
## Glue only: the painting logic lives in GrassBrush (scripts/environment/grass_brush.gd).
## Approved exception to the no-plugin rule (Stage 9); it paints grass masks and nothing else.

const CURSOR_POINTS := 48
const CURSOR_LIFT := 0.05  # metres above the ground, so the line isn't z-fighting
const RADIUS_MIN := 0.5
const RADIUS_MAX := 20.0
const REGROUND_DELAY := 0.3  # seconds a moved field must sit still before its blades re-ground

var _brush := GrassBrush.new()
var _field: GrassField
var _stroke_mode := GrassField.PaintMode.DENSITY  # the toolbar mode, restored after a Shift stroke

var _toolbar: HBoxContainer
var _mode_button: OptionButton
var _radius_box: SpinBox
var _strength_box: SpinBox
var _target_box: SpinBox
var _falloff_box: SpinBox

var _cursor: MeshInstance3D
var _cursor_mesh: ImmediateMesh
var _cursor_material: StandardMaterial3D
var _cursor_at: Variant = null  # last brush position on the ground, or null

var _last_origin := Vector3.INF
var _moved_for := -1.0  # seconds since the field last moved; < 0 = not waiting


func _enter_tree() -> void:
	_build_toolbar()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.hide()


func _exit_tree() -> void:
	_end_stroke()
	_free_cursor()
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()
	_toolbar = null
	_field = null


func _handles(object: Object) -> bool:
	return object is GrassField


func _edit(object: Object) -> void:
	if object == _field:
		return
	_end_stroke()
	_free_cursor()
	_field = object as GrassField
	_last_origin = _field.global_position if _field != null else Vector3.INF
	_moved_for = -1.0


func _make_visible(visible: bool) -> void:
	if _toolbar != null:
		_toolbar.visible = visible
	if not visible:
		_end_stroke()
		_free_cursor()


# A moved field keeps its old blade heights until rebuilt; once it has stopped moving, re-ground
# it (rebuild re-raycasts the ground cache because its origin changed).
func _process(delta: float) -> void:
	if not _field_ok():
		return
	var origin := _field.global_position
	if not origin.is_equal_approx(_last_origin):
		_last_origin = origin
		_moved_for = 0.0
		_hide_cursor()
	elif _moved_for >= 0.0:
		_moved_for += delta
		if _moved_for >= REGROUND_DELAY and not _brush.is_painting():
			_moved_for = -1.0
			_field.mark_dirty()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _field_ok():
		return AFTER_GUI_INPUT_PASS

	var motion := event as InputEventMouseMotion
	if motion != null:
		var hit: Variant = _ground_under(camera, motion.position)
		_show_cursor(hit)
		if _brush.is_painting():
			if hit != null:
				_brush.dab(hit)
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_end_stroke()  # a release outside the viewport may have been missed
			if button.alt_pressed or button.ctrl_pressed or button.meta_pressed:
				return AFTER_GUI_INPUT_PASS  # leave modified clicks to the editor
			var hit: Variant = _ground_under(camera, button.position)
			if hit == null:
				return AFTER_GUI_INPUT_PASS
			_stroke_mode = _brush.mode
			if button.shift_pressed:
				_brush.mode = GrassField.PaintMode.ERASE
			_fork_shared_mask(_field)
			_brush.begin(_field)
			_brush.dab(hit)
			_show_cursor(hit)
			return AFTER_GUI_INPUT_STOP
		if _brush.is_painting():
			_end_stroke()
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_BRACKETLEFT or key.keycode == KEY_BRACKETRIGHT:
			var factor := 0.8 if key.keycode == KEY_BRACKETLEFT else 1.25
			_radius_box.value = clampf(_brush.radius * factor, RADIUS_MIN, RADIUS_MAX)
			return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


# --- stroke ------------------------------------------------------------------------------

func _end_stroke() -> void:
	if not _brush.is_painting():
		return
	var field := _field
	var pair := _brush.end()
	_brush.mode = _stroke_mode
	if pair.is_empty() or not _field_ok() or pair[0].get_data() == pair[1].get_data():
		return
	var saved := _save_mask(field)
	var undo := get_undo_redo()
	# The field as context puts the action in its scene's history; ResourceSaver alone would
	# otherwise ask for the global one.
	undo.create_action("Paint grass", UndoRedo.MERGE_DISABLE, field)
	undo.add_do_method(field, "set_mask_data", pair[1])
	undo.add_undo_method(field, "set_mask_data", pair[0])
	if saved:  # keep the .res file in step with undo / redo
		undo.add_do_method(ResourceSaver, "save", field.mask, "", 0)
		undo.add_undo_method(ResourceSaver, "save", field.mask, "", 0)
	undo.commit_action(false)  # the stroke is already painted


## Gives `field` its own copy of its mask when the mask belongs to another field or scene (a
## Ctrl+D duplicate, or a field pasted from another scene), so _save_mask writes a new
## <scene>_grass[_N].res instead of overwriting the other's file. The fork isn't undoable: the
## stroke's undo restores the copy's pixels, and the original file is never touched.
func _fork_shared_mask(field: GrassField) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var scene_path := root.scene_file_path if root != null else ""
	var others: Array = []
	if root != null:
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is GrassField and node != field:
				others.append((node as GrassField).mask)
	if GrassBrush.mask_needs_fork(field.mask, scene_path, others):
		field.mask = field.mask.duplicate()  # a copy has no resource_path, so it gets a new file


## Writes the mask to its .res file. A mask without a file of its own is saved next to the
## edited scene as <scene_name>_grass.res (or _grass_2.res, ... if that name is taken).
func _save_mask(field: GrassField) -> bool:
	var mask := field.mask
	var path := mask.resource_path
	if not path.is_empty() and not path.contains("::"):
		return ResourceSaver.save(mask) == OK
	var root := EditorInterface.get_edited_scene_root()
	var scene_path := root.scene_file_path if root != null else ""
	if scene_path.is_empty():
		push_warning("Grass Painter: save the scene first; the grass mask is stored next to it.")
		return false
	var base := scene_path.get_basename() + "_grass"
	path = base + ".res"
	var n := 2
	while ResourceLoader.exists(path):
		path = "%s_%d.res" % [base, n]
		n += 1
	if ResourceSaver.save(mask, path) != OK:
		push_error("Grass Painter: could not save the grass mask to %s" % path)
		return false
	mask.take_over_path(path)  # the scene now references the file instead of embedding it
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.mark_scene_as_unsaved()
	return true


# --- brush cursor ------------------------------------------------------------------------

func _ground_under(camera: Camera3D, screen_pos: Vector2) -> Variant:
	return GrassBrush.ray_to_ground(_field, camera.project_ray_origin(screen_pos),
			camera.project_ray_normal(screen_pos))


## Draws the brush circle at `at` (a ground point), following the ground; hides it on null.
func _show_cursor(at: Variant) -> void:
	_cursor_at = at
	if at == null:
		_hide_cursor()
		return
	if _cursor == null:
		_cursor_mesh = ImmediateMesh.new()
		_cursor_material = StandardMaterial3D.new()
		_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cursor_material.no_depth_test = true
		_cursor_material.albedo_color = Color(1.0, 0.85, 0.2)
		_cursor = MeshInstance3D.new()
		_cursor.mesh = _cursor_mesh
		_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cursor.top_level = true  # drawn in world space
		_field.add_child(_cursor, false, Node.INTERNAL_MODE_BACK)  # no owner: never saved
	var centre: Vector3 = at
	_cursor_mesh.clear_surfaces()
	_cursor_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _cursor_material)
	for i in CURSOR_POINTS + 1:  # the last point closes the loop
		var angle := TAU * i / CURSOR_POINTS
		var p := centre + Vector3(cos(angle), 0.0, sin(angle)) * _brush.radius
		var y := _field.ground_height_at(Vector2(p.x, p.z))
		_cursor_mesh.surface_add_vertex(Vector3(p.x, (centre.y if is_nan(y) else y) + CURSOR_LIFT, p.z))
	_cursor_mesh.surface_end()
	_cursor.global_transform = Transform3D.IDENTITY
	_cursor.show()


func _hide_cursor() -> void:
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.hide()


func _free_cursor() -> void:
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.get_parent().remove_child(_cursor)
		_cursor.queue_free()
	_cursor = null
	_cursor_mesh = null
	_cursor_at = null


func _field_ok() -> bool:
	return _field != null and is_instance_valid(_field) and _field.is_inside_tree()


# --- toolbar -----------------------------------------------------------------------------

func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_child(VSeparator.new())
	var title := Label.new()
	title.text = "Grass"
	title.tooltip_text = "LMB paints, Shift + LMB erases, [ / ] shrink / grow the brush."
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	_toolbar.add_child(title)

	_mode_button = OptionButton.new()
	_mode_button.add_item("Density", GrassField.PaintMode.DENSITY)
	_mode_button.add_item("Height", GrassField.PaintMode.HEIGHT)
	_mode_button.add_item("Erase", GrassField.PaintMode.ERASE)
	_mode_button.select(_mode_button.get_item_index(_brush.mode))
	_mode_button.tooltip_text = "What the brush paints. Shift + LMB always erases."
	_mode_button.item_selected.connect(_on_mode_selected)
	_toolbar.add_child(_mode_button)

	_radius_box = _add_spin("Radius", RADIUS_MIN, RADIUS_MAX, 0.1, _brush.radius, " m",
			"Brush radius in metres ([ / ] scale it).", _on_radius_changed)
	_strength_box = _add_spin("Strength", 0.05, 1.0, 0.05, _brush.strength, "",
			"How far each dab moves the mask toward the target.", _on_strength_changed)
	_target_box = _add_spin("Target", 0.0, 1.0, 0.05, _brush.target, "",
			"Density (Density mode) or height (Height mode) to paint toward.", _on_target_changed)
	_falloff_box = _add_spin("Falloff", 0.0, 1.0, 0.05, _brush.falloff, "",
			"Fraction of the radius over which a dab fades out at its rim (0 = hard edge).",
			_on_falloff_changed)


func _on_mode_selected(index: int) -> void:
	_brush.mode = _mode_button.get_item_id(index) as GrassField.PaintMode
	_stroke_mode = _brush.mode


func _on_radius_changed(value: float) -> void:
	_brush.radius = value
	if _cursor_at != null and _field_ok():
		_show_cursor(_cursor_at)


func _on_strength_changed(value: float) -> void:
	_brush.strength = value


func _on_target_changed(value: float) -> void:
	_brush.target = value


func _on_falloff_changed(value: float) -> void:
	_brush.falloff = value


func _add_spin(label: String, lo: float, hi: float, step: float, value: float, suffix: String,
		tooltip: String, on_change: Callable) -> SpinBox:
	var text := Label.new()
	text.text = label
	_toolbar.add_child(text)
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = step
	box.value = value
	box.suffix = suffix
	box.tooltip_text = tooltip
	box.custom_minimum_size.x = 80
	box.value_changed.connect(on_change)
	_toolbar.add_child(box)
	return box
