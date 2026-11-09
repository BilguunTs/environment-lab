extends "res://tests/case.gd"


func test_table_format(_pg) -> void:
	var rows: Array[Dictionary] = [
		{"view": "Camp", "grass": true, "fps": 300.0, "cpu_ms": 1.5, "gpu_ms": 1.234, "draws": 400, "prims": 900000},
		{"view": "Camp", "grass": false, "fps": 400.0, "cpu_ms": 1.2, "gpu_ms": 0.9, "draws": 300, "prims": 500000},
	]
	var lines := PerfHud.table(rows).strip_edges().split("\n")
	check_eq(lines.size(), 4, "header + separator + 2 rows")
	check(lines[1].begins_with("|") and lines[1].contains("---"), "separator row")
	check(lines[2].contains("1.23"), "gpu_ms to 2 decimals")


func test_measure_reads_gpu(pg) -> void:
	if not needs_window():
		return
	var was: bool = pg.perf_hud.visible
	var result: Dictionary = await pg.perf_hud.measure(10)
	check(result.gpu_ms > 0.0, "gpu_ms > 0: %s" % result)
	check(result.draws > 0, "draws > 0")
	check_eq(pg.perf_hud.visible, was, "visibility restored")
