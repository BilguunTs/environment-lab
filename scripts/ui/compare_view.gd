class_name CompareView
extends Control
## Split-screen overlay: the frozen A image left of a draggable divider, the live scene (B)
## to the right. Drag the divider with the left mouse button. Stays visible and simply draws
## nothing when inactive, so the overlay group can hide/restore it during captures.

const HANDLE := 12.0  # px either side of the divider that grab it
const LINE := Color(1, 1, 1, 0.8)
const OUTLINE := Color(0, 0, 0, 0.8)

var compare: Compare
var divider := 0.5  # fraction of the width
var _image: Image  # the image _texture was made from
var _texture: ImageTexture
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_PASS  # unhandled clicks still reach the camera (RMB orbit)
	add_to_group("overlay")


func active() -> bool:
	return compare.split and not compare.showing_a and compare.a_image != null


func _process(_delta: float) -> void:
	if compare.a_image != _image:
		_image = compare.a_image
		_texture = ImageTexture.create_from_image(_image) if _image else null
	queue_redraw()


func _draw() -> void:
	if not active() or _texture == null:
		return
	var x := size.x * divider
	var source := Vector2(_texture.get_width() * divider, _texture.get_height())
	draw_texture_rect_region(_texture, Rect2(Vector2.ZERO, Vector2(x, size.y)), Rect2(Vector2.ZERO, source))
	draw_line(Vector2(x, 0), Vector2(x, size.y), LINE, 2.0)
	draw_rect(Rect2(x - 4, size.y * 0.5 - 24, 8, 48), LINE)
	var font := get_theme_default_font()
	for label in [["A", x - 30.0], ["B", x + 14.0]]:
		draw_string_outline(font, Vector2(label[1], 30), label[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, OUTLINE)
		draw_string(font, Vector2(label[1], 30), label[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LINE)


func _gui_input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and absf(event.position.x - size.x * divider) <= HANDLE:
			_dragging = true
			accept_event()
		elif not event.pressed and _dragging:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		divider = clampf(event.position.x / size.x, 0.02, 0.98)
		accept_event()
