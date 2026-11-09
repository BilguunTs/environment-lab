class_name ValueProbe
extends Control
## Live value readout: luminance under the cursor, frame p5/p50/p95 and a histogram with the
## notan split marked. Measures the final tonemapped frame (what you see, value view included)
## with the same Rec.709 weights as the experiment log. Off by default: every sample reads the
## frame back from the GPU, which costs a few ms.

const SAMPLE_INTERVAL := 0.25
const BINS := 32
const DOWNSAMPLE := 8
const BOX := Vector2(260, 132)
const SPLIT_COLOR := Color(0.95, 0.68, 0.35)

var pg: Node
var cursor_value := -1.0  # -1 = cursor outside the window
var stats := {}
var _timer := 0.0


static func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Percentiles and histogram of `image`, skipping pixels inside `exclude` (image pixel space).
## Reads the raw bytes and walks each row as runs between the excluded x-spans.
static func measure(image: Image, exclude: Array[Rect2] = []) -> Dictionary:
	var hist := PackedInt32Array()
	hist.resize(BINS)
	var source := image
	if source.get_format() != Image.FORMAT_RGB8 and source.get_format() != Image.FORMAT_RGBA8:
		source = image.duplicate()
		source.convert(Image.FORMAT_RGBA8)
	var width := source.get_width()
	var height := source.get_height()
	var bpp := 3 if source.get_format() == Image.FORMAT_RGB8 else 4
	var data := source.get_data()
	var lr := PackedFloat64Array()
	var lg := PackedFloat64Array()
	var lb := PackedFloat64Array()
	for i in 256:
		lr.append(0.2126 * i / 255.0)
		lg.append(0.7152 * i / 255.0)
		lb.append(0.0722 * i / 255.0)
	var values := PackedFloat32Array()
	values.resize(width * height)
	var count := 0
	for y in height:
		# Pixel centres inside a rect, as Rect2.has_point(Vector2(x + 0.5, y + 0.5)) would say.
		var spans: Array[Vector2i] = []
		for r in exclude:
			if y + 0.5 >= r.position.y and y + 0.5 < r.end.y:
				var x0 := clampi(ceili(r.position.x - 0.5), 0, width)
				var x1 := clampi(ceili(r.end.x - 0.5), 0, width)
				if x1 > x0:
					spans.append(Vector2i(x0, x1))
		spans.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		spans.append(Vector2i(width, width))  # sentinel: the run after the last span
		var cursor := 0
		for span in spans:
			for x in range(cursor, span.x):
				var i := (y * width + x) * bpp
				var v := minf(lr[data[i]] + lg[data[i + 1]] + lb[data[i + 2]], 1.0)
				values[count] = v
				count += 1
				hist[mini(int(v * BINS), BINS - 1)] += 1
			cursor = maxi(cursor, span.y)
	if count == 0:
		return {"p5": 0.0, "p50": 0.0, "p95": 0.0, "hist": hist}
	values.resize(count)
	values.sort()
	var n := count
	return {
		"p5": values[mini(int(0.05 * n), n - 1)],
		"p50": values[mini(int(0.5 * n), n - 1)],
		"p95": values[mini(int(0.95 * n), n - 1)],
		"hist": hist,
	}


func _ready() -> void:
	add_to_group("overlay")
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	offset_left = -BOX.x - 16
	offset_top = -BOX.y - 16
	offset_right = -16
	offset_bottom = -16
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer < SAMPLE_INTERVAL:
		return
	_timer = 0.0
	sample()
	queue_redraw()


func sample() -> void:
	var frame := get_viewport().get_texture().get_image()
	if frame == null or frame.is_empty():
		return
	var mouse := get_viewport().get_mouse_position()
	var full := Rect2(Vector2.ZERO, Vector2(frame.get_size()))
	cursor_value = luminance(frame.get_pixelv(Vector2i(mouse))) if full.has_point(mouse) else -1.0
	frame.resize(frame.get_width() / DOWNSAMPLE, frame.get_height() / DOWNSAMPLE, Image.INTERPOLATE_BILINEAR)
	# Skip the panel, HUD and this box; full-screen overlays (split view) are part of the picture.
	var exclude: Array[Rect2] = []
	for node in get_tree().get_nodes_in_group("overlay"):
		if node is Control and node.is_visible_in_tree():
			var r: Rect2 = node.get_global_rect()
			if r.get_area() < full.get_area() * 0.5:
				exclude.append(Rect2(r.position / DOWNSAMPLE, r.size / DOWNSAMPLE))
	stats = measure(frame, exclude)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BOX), Color(0.05, 0.055, 0.06, 0.86))
	if stats.is_empty():
		return
	var plot := Rect2(10, 10, BOX.x - 20, 70)
	var hist: PackedInt32Array = stats["hist"]
	var peak := 1
	for count in hist:
		peak = maxi(peak, count)
	var bar := plot.size.x / BINS
	for i in BINS:
		var h := plot.size.y * hist[i] / float(peak)
		var shade := 0.25 + 0.75 * (i + 0.5) / BINS
		draw_rect(Rect2(plot.position.x + i * bar, plot.end.y - h, bar - 1.0, h), Color(shade, shade, shade))
	for q in ["p5", "p50", "p95"]:
		var qx: float = plot.position.x + plot.size.x * float(stats[q])
		draw_line(Vector2(qx, plot.position.y), Vector2(qx, plot.end.y), Color(1, 1, 1, 0.6), 1.0)
	var split: float = pg.get_param("value_split")
	var sx := plot.position.x + plot.size.x * split
	draw_line(Vector2(sx, plot.position.y - 4), Vector2(sx, plot.end.y + 4), SPLIT_COLOR, 2.0)
	var font := get_theme_default_font()
	var cursor := "—" if cursor_value < 0.0 else "%.2f" % cursor_value
	draw_string(font, Vector2(10, 100), "cursor %s   split %.2f" % [cursor, split], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(10, 120), "p5 %.2f   p50 %.2f   p95 %.2f" % [stats["p5"], stats["p50"], stats["p95"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
