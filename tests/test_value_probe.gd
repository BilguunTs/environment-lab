extends "res://tests/case.gd"


func after_each(pg) -> void:
	pg.set_param("probe", false)


func _half_and_half() -> Image:
	var image := Image.create_empty(10, 10, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, 5, 10), Color.BLACK)
	image.fill_rect(Rect2i(5, 0, 5, 10), Color.WHITE)
	return image


func test_luminance_weights(_pg) -> void:
	check_near(ValueProbe.luminance(Color(0, 1, 0)), 0.7152, 0.0001, "Rec.709 green weight")


func test_measure_half_black_half_white(_pg) -> void:
	var s := ValueProbe.measure(_half_and_half())
	check_near(s["p5"], 0.0, 0.001, "p5 is black")
	check_near(s["p95"], 1.0, 0.001, "p95 is white")
	check_eq(s["hist"][0], 50, "50 black pixels in the first bin")
	check_eq(s["hist"][ValueProbe.BINS - 1], 50, "50 white pixels in the last bin")


func test_measure_skips_excluded_rects(_pg) -> void:
	var exclude: Array[Rect2] = [Rect2(5, 0, 5, 10)]
	var s := ValueProbe.measure(_half_and_half(), exclude)
	check_near(s["p95"], 0.0, 0.001, "white half excluded")
	check_eq(s["hist"][ValueProbe.BINS - 1], 0, "no white counted")


func test_probe_matches_stage7_measurements(pg) -> void:
	if not needs_window():
		return
	pg.set_param("view", "Forest Gate")
	pg.set_param("probe", true)
	await seconds(0.6)
	check(pg.probe.stats.has("p50"), "probe produced stats")
	pg.hide_overlays()
	await frames(2)
	await RenderingServer.frame_post_draw
	var frame: Image = pg.get_viewport().get_texture().get_image()
	pg.restore_overlays()
	var sky: float = ValueProbe.measure(frame.get_region(Rect2i(600, 60, 400, 60)))["p50"]
	check_near(sky, 0.60, 0.03, "sky matches the Stage 7 manual measurement")
	# The hole breathes (±30 %), so check it's the light point rather than an exact value.
	var hole: float = ValueProbe.measure(frame.get_region(Rect2i(824, 240, 9, 9)))["p95"]
	check(hole > 0.75, "the hole is the brightest point (Stage 7: 0.86), got %.2f" % hole)


func test_sample_cost(pg) -> void:
	if not needs_window():
		return
	pg.set_param("probe", true)
	await frames(3)
	var start := Time.get_ticks_usec()
	pg.probe.sample()
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	print("     probe sample: %.1f ms" % ms)
	check(ms < 60.0, "one probe sample stays under 60 ms (got %.1f)" % ms)


func test_measure_known_gradient(_pg) -> void:
	var image := Image.create_empty(100, 1, false, Image.FORMAT_RGB8)
	for x in 100:
		var g := x / 99.0
		image.set_pixel(x, 0, Color(g, g, g))
	var s := ValueProbe.measure(image)
	check_near(s["p5"], 5 / 99.0, 0.005, "p5 is pixel 5")
	check_near(s["p50"], 50 / 99.0, 0.005, "p50 is pixel 50")
	check_near(s["p95"], 95 / 99.0, 0.005, "p95 is pixel 95")
	var total := 0
	for count in s["hist"]:
		total += count
	check_eq(total, 100, "every pixel is in the histogram")


func test_measure_is_fast(_pg) -> void:
	var image := Image.create_empty(200, 113, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.5, 0.6))
	var exclude: Array[Rect2] = [Rect2(0, 0, 40, 113), Rect2(150, 10, 40, 30), Rect2(60, 80, 70, 20)]
	var s := {}
	var ms := INF
	for _i in 3:  # best of 3: a single run flakes under full-suite load
		var start := Time.get_ticks_usec()
		s = ValueProbe.measure(image, exclude)
		ms = minf(ms, (Time.get_ticks_usec() - start) / 1000.0)
	print("     measure: %.2f ms" % ms)
	check(ms < 4.0, "measure() under 4 ms (got %.2f)" % ms)
	var total := 0
	for count in s["hist"]:
		total += count
	check_eq(total, 200 * 113 - 40 * 113 - 40 * 30 - 70 * 20, "excluded pixels not counted")
