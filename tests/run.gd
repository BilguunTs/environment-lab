extends SceneTree
## Runs every tests/test_*.gd against a live scene: the playground, or the scene a file names with
## `const SCENE := "res://..."`. A scene root with reset_scene() gets it called before each test.
##   Godot --path . -s res://tests/run.gd                  all tests (opens a window)
##   Godot --headless --path . -s res://tests/run.gd       logic only; image tests are skipped
##   Godot --path . -s res://tests/run.gd -- --only=name   files whose name contains "name"
## Exit code 0 = everything passed.

const TEST_DIR := "res://tests"
const DEFAULT_SCENE := "res://scenes/playground.tscn"


## Collects engine and script errors: a runtime error aborts a test function silently, so
## without this a crashed test would still report PASS.
class ErrorCatcher extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out := errors.duplicate()
		errors.clear()
		_mutex.unlock()
		return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var passed := 0
	var failed := 0
	var skipped := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR))
	files.sort()
	# Group the test files by the scene they run against (const SCENE, default: the playground).
	# Each distinct scene is instantiated once; the playground group runs first.
	var scenes: Array[String] = [DEFAULT_SCENE]
	var by_scene := {DEFAULT_SCENE: []}
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		if only != "" and not file.contains(only):
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		catcher.take()  # a parse error is reported below as a FAIL of its own
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL %s (does not parse; see the error above)" % file)
			continue
		var scene_path: String = script.get_script_constant_map().get("SCENE", DEFAULT_SCENE)
		if not by_scene.has(scene_path):
			by_scene[scene_path] = []
			scenes.append(scene_path)
		by_scene[scene_path].append([file, script])
	for scene_path in scenes:
		if by_scene[scene_path].is_empty():
			continue
		var pg: Node = load(scene_path).instantiate()
		root.add_child(pg)
		for i in 30:  # let shadows, SSAO and the forest settle
			await process_frame
		for entry: Array in by_scene[scene_path]:
			var file: String = entry[0]
			var script: GDScript = entry[1]
			for method in script.get_script_method_list():
				var test_name: String = method["name"]
				if not test_name.begins_with("test_"):
					continue
				var case = script.new()
				case.tree = self
				if pg.has_method("reset_scene"):
					pg.reset_scene()
				catcher.take()  # errors before this test aren't its fault
				if case.has_method("before_each"):
					await case.before_each(pg)
				await case.call(test_name, pg)
				if case.has_method("after_each"):
					await case.after_each(pg)
				for error in catcher.take():
					if not case.expected_errors.any(func(fragment: String) -> bool: return error.contains(fragment)):
						case.failures.append("engine/script error: " + error)
				var label := "%s::%s" % [file.get_basename(), test_name]
				if case.skipped != "":
					skipped += 1
					print("SKIP %s (%s)" % [label, case.skipped])
				elif case.failures.is_empty():
					passed += 1
					print("PASS %s" % label)
				else:
					failed += 1
					print("FAIL %s" % label)
					for message in case.failures:
						print("     - %s" % message)
		root.remove_child(pg)
		pg.free()
		await process_frame
	print("\n%d passed, %d failed, %d skipped" % [passed, failed, skipped])
	quit(1 if failed > 0 else 0)
