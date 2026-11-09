extends "res://tests/case.gd"

const Presets := preload("res://scripts/presets.gd")
const PATH := "user://test_presets.cfg"


func before_each(_pg) -> void:
	_remove()


func after_each(_pg) -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_overrides_keep_only_changed_keys(_pg) -> void:
	var base := {"a": 1.0, "b": Color(1, 0, 0), "c": true}
	var state := {"a": 1.0000001, "b": Color(0, 1, 0), "c": true}
	check_eq(Presets.overrides(state, base).keys(), ["b"], "only the colour changed")


func test_save_then_all_round_trips_values(pg) -> void:
	var state: Dictionary = pg.get_state()
	state["sun_glow"] = 0.6
	state["sun_color"] = Color(1, 0.5, 0.25)
	check_eq(Presets.save_user("My Dusk", state, pg.get_state(), PATH), "", "save succeeds")
	var preset: Dictionary = Presets.all(PATH)["My Dusk"]
	check_near(preset["sun_glow"], 0.6, 0.0001, "sun_glow saved")
	check(preset["sun_color"].is_equal_approx(Color(1, 0.5, 0.25)), "colour saved")
	check_eq(preset["view"], "Gameplay", "view always saved")
	check_eq(preset.size(), 3, "only overrides plus view are saved")


func test_saving_same_name_overwrites(pg) -> void:
	var state: Dictionary = pg.get_state()
	state["sun_glow"] = 0.6
	Presets.save_user("X", state, pg.get_state(), PATH)
	state["sun_glow"] = 0.3
	Presets.save_user("X", state, pg.get_state(), PATH)
	check_near(Presets.all(PATH)["X"]["sun_glow"], 0.3, 0.0001, "second save wins")


func test_rejects_bad_names(pg) -> void:
	var s: Dictionary = pg.get_state()
	check(Presets.save_user("   ", s, s, PATH) != "", "blank name refused")
	check(Presets.save_user("Moonlit", s, s, PATH) != "", "built-in name refused")
	check(Presets.save_user("Reset", s, s, PATH) != "", "Reset refused")
	check(Presets.save_user("a]b", s, s, PATH) != "", "section-breaking name refused")
	check(not FileAccess.file_exists(PATH), "nothing written for refused names")


func test_broken_file_is_not_overwritten(pg) -> void:
	expect_error("ConfigFile parse error")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("[Broken\nsun_glow = \n")
	f.close()
	var s: Dictionary = pg.get_state()
	check(Presets.save_user("New", s, s, PATH) != "", "save refuses to clobber an unreadable file")
	check_eq(FileAccess.get_file_as_string(PATH), "[Broken\nsun_glow = \n", "file untouched")
	check(Presets.all(PATH).has("Moonlit"), "built-ins still load")


func test_missing_file_means_builtins_only(_pg) -> void:
	check_eq(Presets.all(PATH).size(), Presets.ALL.size(), "no user presets")
