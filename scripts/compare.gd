class_name Compare
extends Node
## A/B comparison from one camera. A is a pinned state; B is always the live scene.
## P pins A, hold X to see A, Z splits the screen (frozen A image | live B). Talks to the scene
## only through the playground's get_state / apply_state interface, so every parameter is
## comparable for free.

signal changed  # pinned, flipped, split toggled or A re-captured: HUD and panel refresh

const Presets := preload("res://scripts/presets.gd")
## Not compared: A and B are seen from the same camera, guides and value view.
const EXCLUDE := ["view", "guides_grid", "guides_center", "guides_aspect", "value_mode", "value_squint", "value_split"]
const SETTLE_FRAMES := 10  # volumetric fog and shadows need a few frames to catch up
const RECAPTURE_DELAY := 0.5  # s the camera must be still before A re-renders in split view
const STRIP_LINE := 20  # px per text line under a saved pair

var pg: Node  # the playground
var a_state := {}  # empty = nothing pinned
var _a_view := ""  # the view A was pinned in: its cam_fov only means something there
var showing_a := false
var _b_state := {}  # the live state while A is shown
var _release_pending := false  # X was released mid-capture: return to B when it ends
var split := false
var a_image: Image  # A rendered from the current camera (split view)
var busy := false  # a capture is running: flips and new captures wait
var view: CompareView
var _dirty := false
var _still := 0.0
var _last_cam := Transform3D()
var _last_fov := 0.0


func has_a() -> bool:
	return not a_state.is_empty()


func compare_state() -> Dictionary:
	var state: Dictionary = pg.get_state()
	for key in EXCLUDE:
		state.erase(key)
	return state


## Why A/B can't run right now, or "" if it can.
func blocked_reason(needs_a := true) -> String:
	if pg.in_scout():
		return "Leave Scout first (F)"
	if needs_a and not has_a():
		return "Pin A first (P)"
	return ""


func pin() -> void:
	var reason := blocked_reason(false)
	if reason != "":
		pg.panel.notify(reason)
		return
	show_a(false)
	a_state = compare_state()
	_a_view = pg.get_param("view")
	pg.panel.notify("A pinned: change something, then hold X to compare")
	changed.emit()
	request_recapture(true)  # in split view the left half must show the new A


func clear() -> void:
	leave()
	a_state = {}
	changed.emit()


## Back to plain B, e.g. before Scout takes over the camera.
func leave() -> void:
	show_a(false)
	if split:
		split = false
		changed.emit()


## Hold-to-flip: true shows A, false returns to the live state B.
func show_a(on: bool) -> void:
	if busy:
		if not on and showing_a:
			_release_pending = true  # honoured when the capture ends
		return
	if on == showing_a:
		return
	if on:
		var reason := blocked_reason()
		if reason != "":
			pg.panel.notify(reason)
			return
		_b_state = compare_state()
		_apply(_a_here())
	else:
		_apply(_b_state)
	showing_a = on
	changed.emit()


## "key: a → b" for every compared parameter that differs between A and B, in panel order.
func diff() -> Array[String]:
	if not has_a():
		return []
	return diff_between(_a_here(), _b_state if showing_a else compare_state())


## Applies a state and snaps the smoothed camera, so A and B cut instead of gliding.
func _apply(state: Dictionary) -> void:
	pg.apply_state(state)
	pg.settle_camera()


## A as it applies to the current view. cam_fov is the *active* camera's lens, so after a view
## change A's lens belongs to another camera and must not be pushed onto this one.
func _a_here() -> Dictionary:
	var a := a_state.duplicate()
	if pg.get_param("view") != _a_view:
		a.erase("cam_fov")
	return a


static func diff_between(a: Dictionary, b: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in a:
		if b.has(key) and not Presets.same_value(a[key], b[key]):
			lines.append("%s: %s → %s" % [key, fmt(a[key]), fmt(b[key])])
	return lines


## Short, log-friendly value text: 3 significant digits, colours as hex, booleans as on/off.
static func fmt(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "on" if value else "off"
		TYPE_COLOR:
			return "#" + value.to_html(false)
		TYPE_FLOAT, TYPE_INT:
			var v := float(value)
			if v == roundf(v):
				return str(int(v))
			var decimals := clampi(2 - floori(log(absf(v)) / log(10.0)), 0, 6)
			return String.num(v, decimals)
	return str(value)


func hud_tag() -> String:
	if not has_a():
		return ""
	if showing_a:
		return "SHOWING A"  # X held: the split overlay steps aside, so say what's on screen
	if split:
		return "SPLIT  A | B"
	return "B · A pinned"


func attach_view(ui: CanvasLayer, below: Control) -> void:
	view = CompareView.new()
	view.compare = self
	ui.add_child(view)
	ui.move_child(view, below.get_index())  # under the dev panel, over the 3D view and value view


func toggle_split() -> void:
	if busy:
		return
	if not split:
		var reason := blocked_reason()
		if reason != "":
			pg.panel.notify(reason)
			return
	show_a(false)
	split = not split
	changed.emit()
	if split:
		await capture_a()


## Renders `state` from the current camera with the overlays hidden and returns the frame.
## Leaves `state` applied: callers restore what they need.
func render_state(state: Dictionary) -> Image:
	pg.hide_overlays()
	_apply(state)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	pg.restore_overlays()
	return image


## Re-renders the frozen A image for split view. Costs a SETTLE_FRAMES blink.
func capture_a() -> void:
	if busy or not has_a():
		return
	busy = true
	_dirty = false  # anything that re-dirties during the capture triggers another one
	var b := compare_state()
	# Sampled before the blink: a move during it must still differ afterwards and recapture.
	var cam := get_viewport().get_camera_3d()
	if cam:
		_last_cam = cam.global_transform
		_last_fov = cam.fov
	a_image = await render_state(_a_here())
	_apply(b)
	_end_busy()
	changed.emit()


func _end_busy() -> void:
	busy = false
	if _release_pending:
		_release_pending = false
		show_a(false)


## Re-render A (e.g. the value view changed and is baked into A). Debounced like camera moves,
## so dragging a slider renders once when it rests; `now` skips the wait.
func request_recapture(now := false) -> void:
	if split:
		_dirty = true
		_still = RECAPTURE_DELAY if now else 0.0


func _process(delta: float) -> void:
	if not split or busy or showing_a:  # holding X hides the overlay; don't capture under it
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not cam.global_transform.is_equal_approx(_last_cam) or not is_equal_approx(cam.fov, _last_fov):
		_last_cam = cam.global_transform
		_last_fov = cam.fov
		_still = 0.0
		_dirty = true
	elif _dirty:
		_still += delta
		if _still >= RECAPTURE_DELAY:
			capture_a()


## Renders A and B properly (not cropped from the split view), saves them side by side with
## the diff underneath, and copies a ready experiment-log row. Returns the PNG path or "".
func save_pair() -> String:
	var reason := blocked_reason()
	if reason != "" or busy:
		pg.panel.notify(reason if reason != "" else "Still capturing, try again")
		return ""
	show_a(false)
	busy = true
	var b := compare_state()
	var a := _a_here()
	var lines := diff_between(a, b)
	var image_a := await render_state(a)
	var image_b := await render_state(b)
	_end_busy()
	var view_name: String = pg.get_param("view")
	var header := "%s · %s · A (left) vs B (right)" % [Time.get_datetime_string_from_system(false, true), view_name]
	var sheet := await compose(image_a, image_b, header, lines)
	var path: String = pg.screenshot_path("compare_" + view_name)
	var error := save_sheet(sheet, path)
	if error != "":
		pg.panel.notify(error)
		changed.emit()
		return ""
	DisplayServer.clipboard_set(log_row(lines))
	pg.panel.notify("Saved %s (log row copied)" % path.get_file())
	changed.emit()
	return path


## Saves the sheet as PNG. Returns "" on success, otherwise a message for the status line.
static func save_sheet(image: Image, path: String) -> String:
	var err := image.save_png(path)
	return "" if err == OK else "Could not save %s (error %d)" % [path.get_file(), err]


## An EXPERIMENT_LOG.md row with Date and Changed filled in; Question, Fixed and Result are yours.
static func log_row(lines: Array[String]) -> String:
	var changed_text := ", ".join(PackedStringArray(lines)) if not lines.is_empty() else "(nothing)"
	return "| %s | | %s | | |" % [Time.get_date_string_from_system(), changed_text]


## Two frames side by side with a text strip below. Godot's Image can't draw text, so this lays
## the pieces out in a temporary 2D SubViewport and grabs its frame.
func compose(left: Image, right: Image, header: String, lines: Array[String]) -> Image:
	var w := left.get_width()
	var h := left.get_height()
	var sub := SubViewport.new()
	sub.size = Vector2i(w * 2, h + STRIP_LINE * (maxi(lines.size(), 1) + 2))
	sub.disable_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	var background := ColorRect.new()
	background.color = Color(0.05, 0.055, 0.06)
	background.size = Vector2(sub.size)
	sub.add_child(background)
	for i in 2:
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(left if i == 0 else right)
		rect.position = Vector2(w * i, 0)
		rect.size = Vector2(w, h)
		sub.add_child(rect)
	var label := Label.new()
	label.position = Vector2(12, h + 6)
	label.add_theme_font_size_override("font_size", 14)
	label.text = header + "\n" + ("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "No differences: A = B")
	sub.add_child(label)
	add_child(sub)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := sub.get_texture().get_image()
	sub.queue_free()
	return image
