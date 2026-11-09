extends "res://tests/case.gd"

const Presets := preload("res://scripts/presets.gd")
const PATH := "user://test_presets_ui.cfg"


func before_each(pg) -> void:
	_remove()
	pg.preset_path = PATH
	pg.panel.refresh_presets()


func after_each(pg) -> void:
	_remove()
	pg.preset_path = Presets.USER_PATH
	pg.panel.refresh_presets()
	pg.set_typing(false)


func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_saved_preset_appears_and_loads(pg) -> void:
	pg.set_param("sun_glow", 0.7)
	check(pg.save_preset("Glowy"), "save succeeds")
	check(pg.panel.preset_buttons().has("Glowy"), "button added to the grid")
	pg.reset_scene()
	pg.apply_preset("Glowy")
	check_near(pg.get_param("sun_glow"), 0.7, 0.001, "loading restores the value")


func test_refused_name_keeps_grid(pg) -> void:
	var before: PackedStringArray = pg.panel.preset_buttons()
	check(not pg.save_preset("Moonlit"), "built-in name refused")
	check_eq(pg.panel.preset_buttons(), before, "grid unchanged")


func test_unknown_preset_is_ignored(pg) -> void:
	pg.apply_preset("Nope")
	check_eq(pg.get_param("view"), "Gameplay", "nothing applied")


func test_typing_blocks_player_movement(pg) -> void:
	pg.set_typing(true)
	check(not pg.player.input_enabled, "player ignores WASD while typing")
	pg.set_typing(false)
	check(pg.player.input_enabled, "player moves again after typing")


func test_clicking_the_scene_ends_typing(pg) -> void:
	pg.panel._preset_name.grab_focus()
	await frames(1)
	check(not pg.player.input_enabled, "focus on the name field = typing")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(1200, 450)  # middle of the 3D view, away from the panel
	pg.panel._input(click)
	await frames(1)
	check(not pg.panel._preset_name.has_focus(), "name field let go of focus")
	check(pg.player.input_enabled, "WASD works again")
