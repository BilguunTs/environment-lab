class_name CompositionGuides
extends Control
## Screen-space framing overlay: compositional grids, a centre marker and aspect-ratio masks.
## Grids are drawn inside the masked frame, so they always describe the final picture.

const GRIDS := ["Off", "Thirds", "Golden", "Diagonals"]
## Width / height. "Screen" = no mask.
const ASPECTS := {"Screen": 0.0, "2.39:1": 2.39, "1.85:1": 1.85, "4:3": 4.0 / 3.0, "1:1": 1.0}
const PHI_MINOR := 0.381966  # 1 - 1/phi

@export_enum("Off", "Thirds", "Golden", "Diagonals") var grid := "Off":
	set(v):
		grid = v
		queue_redraw()
@export var show_center := false:
	set(v):
		show_center = v
		queue_redraw()
@export var aspect := "Screen":
	set(v):
		aspect = v
		queue_redraw()
@export var line_color := Color(1, 1, 1, 0.35)
@export var center_color := Color(1, 0.6, 0.3, 0.8)
@export var mask_color := Color(0, 0, 0, 1)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func cycle_grid() -> void:
	grid = GRIDS[(GRIDS.find(grid) + 1) % GRIDS.size()]


## The visible picture area after the aspect mask is applied.
func frame_rect() -> Rect2:
	var ratio: float = ASPECTS.get(aspect, 0.0)
	if ratio <= 0.0:
		return Rect2(Vector2.ZERO, size)
	if size.x / size.y > ratio:  # screen is wider: pillarbox
		var w := size.y * ratio
		return Rect2(Vector2((size.x - w) * 0.5, 0), Vector2(w, size.y))
	var h := size.x / ratio  # screen is taller: letterbox
	return Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(size.x, h))


func _draw() -> void:
	var r := frame_rect()
	if r.size != size:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, r.position.y)), mask_color)
		draw_rect(Rect2(Vector2(0, r.end.y), Vector2(size.x, size.y - r.end.y)), mask_color)
		draw_rect(Rect2(Vector2.ZERO, Vector2(r.position.x, size.y)), mask_color)
		draw_rect(Rect2(Vector2(r.end.x, 0), Vector2(size.x - r.end.x, size.y)), mask_color)

	match grid:
		"Thirds":
			_draw_split(r, 1.0 / 3.0)
		"Golden":
			_draw_split(r, PHI_MINOR)
		"Diagonals":
			_draw_diagonals(r)

	if show_center:
		var c := r.get_center()
		draw_line(c - Vector2(14, 0), c + Vector2(14, 0), center_color, 1.5)
		draw_line(c - Vector2(0, 14), c + Vector2(0, 14), center_color, 1.5)
		draw_arc(c, 7.0, 0.0, TAU, 24, center_color, 1.5)


## Two vertical and two horizontal lines at `t` and `1 - t` of the frame.
func _draw_split(r: Rect2, t: float) -> void:
	for f: float in [t, 1.0 - t]:
		var x := r.position.x + r.size.x * f
		var y := r.position.y + r.size.y * f
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), line_color, 1.0)
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), line_color, 1.0)


## "Harmonious triangles": both diagonals plus the perpendiculars dropped onto them
## from the remaining corners. Strong lines and subjects tend to sit on these.
func _draw_diagonals(r: Rect2) -> void:
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var bl := Vector2(r.position.x, r.end.y)
	var br := r.end
	for d: Array in [[tl, br, tr, bl], [tr, bl, tl, br]]:
		var a: Vector2 = d[0]
		var b: Vector2 = d[1]
		draw_line(a, b, line_color, 1.0)
		for p: Vector2 in [d[2], d[3]]:
			var dir := b - a
			var foot := a + dir * ((p - a).dot(dir) / dir.length_squared())
			draw_line(p, foot, line_color, 1.0)
