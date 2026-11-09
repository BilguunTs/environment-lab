extends "res://tests/case.gd"


func after_each(pg) -> void:
	pg.set_param("perf_hud", false)


func test_format(_pg) -> void:
	check_eq(PerfHud.format(842.4, 0.51, 1.18, 312, 1_234_567, false),
		"842 fps   CPU 0.51 ms   GPU 1.18 ms\n312 draws   1.2M prims", "readout")
	check_eq(PerfHud.format(60.0, 1.0, 1.0, 5, 45_300, false), "60 fps   CPU 1.00 ms   GPU 1.00 ms\n5 draws   45k prims", "thousands")
	check(PerfHud.format(60.0, 1.0, 1.0, 1, 1, true).contains("probe on"), "flags the probe's cost")


func test_hud_updates_when_on(pg) -> void:
	pg.set_param("perf_hud", true)
	await seconds(PerfHud.INTERVAL + 0.3)
	check(pg.perf_hud.text.contains("fps"), "readout filled in")
	check(not pg.get_state().has("perf_hud"), "not scene state")


func test_cpu_ms_is_work_not_frame_time(pg) -> void:
	if not needs_window():
		return
	pg.set_param("perf_hud", true)
	await seconds(PerfHud.INTERVAL * 2 + 0.2)
	var numbers := RegEx.create_from_string(r"^(\d+) fps\s+CPU ([\d.]+) ms").search(pg.perf_hud.text)
	check(numbers != null, "readout parses: %s" % pg.perf_hud.text)
	if numbers:
		var frame_ms := 1000.0 / float(numbers.get_string(1))
		var cpu_ms := float(numbers.get_string(2))
		check(cpu_ms < frame_ms, "CPU %.2f ms must be work, not the whole %.2f ms frame (vsync wait included)" % [cpu_ms, frame_ms])
