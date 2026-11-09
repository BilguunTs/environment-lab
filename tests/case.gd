extends RefCounted
## Base for test files. tests/test_*.gd extend this and define `test_*` methods taking the
## playground; methods may await. A failed check records a message and the test carries on.

var tree: SceneTree
var failures: Array[String] = []
var skipped := ""
var expected_errors: Array[String] = []  # engine errors this test provokes on purpose


## Declares that the test deliberately triggers an engine error containing `fragment`.
func expect_error(fragment: String) -> void:
	expected_errors.append(fragment)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	var numeric := typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]
	var same: bool = float(actual) == float(expected) if numeric else (typeof(actual) == typeof(expected) and actual == expected)
	if not same:
		failures.append("%s: expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %.3f ± %.3f, got %.3f" % [message, expected, tolerance, actual])


func frames(count: int) -> void:
	for i in count:
		await tree.process_frame


## Waits `count` physics ticks and then one whole _process pass, so a value updated in
## _physics_process (progress, respawn) and anything applied from it in _process (the mood) are
## both current. Process frames alone don't guarantee a physics tick (fast frames), and a slow
## frame can run every tick at once; process_frame fires *before* nodes' _process, hence two.
func physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame
	await tree.process_frame
	await tree.process_frame


func seconds(duration: float) -> void:
	await tree.create_timer(duration).timeout


## Image tests need a real renderer: the headless display server draws nothing.
## Usage: `if not needs_window(): return`
func needs_window() -> bool:
	if DisplayServer.get_name() == "headless":
		skipped = "needs a window (run without --headless)"
		return false
	return true
