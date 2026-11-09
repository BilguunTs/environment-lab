class_name PerfHud
extends Label
## Live cost readout (top right, under the view HUD): fps, CPU and GPU frame time, draw calls
## and primitives, averaged over INTERVAL. At 800+ fps, milliseconds are the honest unit.

const INTERVAL := 0.5

var pg: Node
var _timer := 0.0
var _frames := 0
var _cpu := 0.0
var _gpu := 0.0


static func format(fps: float, cpu_ms: float, gpu_ms: float, draw_calls: int, primitives: int, probe_on: bool) -> String:
	var text := "%d fps   CPU %.2f ms   GPU %.2f ms\n%d draws   %s prims" % [roundi(fps), cpu_ms, gpu_ms, draw_calls, _short(primitives)]
	if probe_on:
		text += "\nprobe on: its readback adds a few ms every 0.25 s"
	return text


## A Markdown table, one row per {view, grass, fps, cpu_ms, gpu_ms, draws, prims}.
static func table(rows: Array[Dictionary]) -> String:
	var lines := PackedStringArray([
		"| View | Grass | FPS | CPU ms | GPU ms | Draws | Prims |",
		"|---|---|---:|---:|---:|---:|---:|",
	])
	for r in rows:
		lines.append("| %s | %s | %d | %.2f | %.2f | %d | %s |" % [r.view, "on" if r.grass else "off", roundi(r.fps),
			r.cpu_ms, r.gpu_ms, r.draws, _short(int(r.prims))])
	return "\n".join(lines) + "\n"


static func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (n / 1_000_000.0)
	if n >= 1000:
		return "%dk" % roundi(n / 1000.0)
	return str(n)


func _ready() -> void:
	add_to_group("overlay")
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	grow_horizontal = GROW_DIRECTION_BEGIN
	offset_left = -440
	offset_right = -16
	offset_top = 64  # until the first update places it under the view HUD
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color(0.75, 1.0, 0.75, 0.9))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("outline_size", 4)
	visible = false
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)
	_reset()


func _reset() -> void:
	_timer = 0.0
	_frames = 0
	_cpu = 0.0
	_gpu = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	var view_hud: Control = pg._hud
	if view_hud:  # the view HUD's height changes with its intent text and the window width
		offset_top = view_hud.position.y + maxf(view_hud.size.y, view_hud.get_combined_minimum_size().y) + 8.0
	var rid := get_viewport().get_viewport_rid()
	# Work only: TIME_PROCESS would be the whole frame, vsync wait included.
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_frames += 1
	_timer += delta
	if _timer < INTERVAL:
		return
	text = format(Performance.get_monitor(Performance.TIME_FPS), _cpu / _frames, _gpu / _frames,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), pg.get_param("probe"))
	_reset()


## Averages fps, CPU/GPU ms, draws and prims over frame_count frames, with the same sources as the
## readout. Turns render-time measuring on for the duration and restores it afterwards.
func measure(frame_count: int) -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for _f in 2:  # the first measured frames are not yet valid
		await get_tree().process_frame
	var cpu := 0.0
	var gpu := 0.0
	var fps := 0.0
	var draws := 0.0
	var prims := 0.0
	for _f in frame_count:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		fps += Performance.get_monitor(Performance.TIME_FPS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	RenderingServer.viewport_set_measure_render_time(rid, visible)
	var n := float(maxi(frame_count, 1))
	return {"fps": fps / n, "cpu_ms": cpu / n, "gpu_ms": gpu / n, "draws": int(draws / n), "prims": int(prims / n)}
