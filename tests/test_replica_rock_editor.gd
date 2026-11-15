extends "res://tests/case.gd"
## The 2D rock correction tool (scripts/replica/rock_editor.gd) on a synthetic fixture site
## (tests/fixtures/replica_site: 100 x 100 m, three rocks, no imagery). Each test works on a fresh
## copy of the fixture under user:// so the committed fixture is never written.

const SCENE := "res://scenes/replica/rock_editor.tscn"
const FIXTURE := "res://tests/fixtures/replica_site"
const WORK := "user://replica_site_test"

var site := ""


func before_each(editor) -> void:
	site = ProjectSettings.globalize_path(WORK)
	_copy_tree(ProjectSettings.globalize_path(FIXTURE), site)
	editor.load_site(site)


func _copy_tree(from: String, to: String) -> void:
	if DirAccess.dir_exists_absolute(to):
		_remove_tree(to)
	DirAccess.make_dir_recursive_absolute(to)
	for file in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(file), to.path_join(file))
	for dir in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(dir), to.path_join(dir))


func _remove_tree(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	DirAccess.remove_absolute(path)


func _edits() -> Dictionary:
	var text := FileAccess.get_file_as_string(site.path_join("edits/rocks_edits.json"))
	var data: Variant = JSON.parse_string(text)
	return data if data is Dictionary else {}


func _write_edits(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(site.path_join("edits"))
	var f := FileAccess.open(site.path_join("edits/rocks_edits.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, " "))
	f.close()


func test_delete_writes_edit(editor) -> void:
	check_eq(editor.select_at(Vector2(-18.0, 8.0)), "fixtureA0001", "click on boulder A selects it")
	editor.delete_selected()
	editor.save()
	var edits := _edits()
	check(Array(edits.get("deleted", [])).has("fixtureA0001"), "id in deleted: %s" % edits)
	check_eq(editor.rocks.size(), 2, "deleted rock leaves the view")


func test_add_writes_edit(editor) -> void:
	var id: String = editor.add_rock(Vector2(30.0, -30.0), 3.0, 2.0, 45.0, 1.5)
	editor.save()
	var added: Array = _edits().get("added", [])
	check_eq(added.size(), 1, "one added rock")
	if added.size() == 1:
		var r: Dictionary = added[0]
		check_eq(r["id"], id, "id")
		check_eq(r["source"], "edit", "source")
		check_eq(r["kind"], "boulder", "kind")
		check_eq([r["x"], r["z"], r["length"], r["width"], r["yaw_deg"], r["height"]],
			[30.0, -30.0, 3.0, 2.0, 45.0, 1.5], "geometry")
		check_eq(r["height_source"], "shadow", "a given height is a measurement")
		check(r.has("outline") and r["outline"] == null, "boulders have no outline")


func test_never_touches_rocks_json(editor) -> void:
	var paths: Array[String] = [site.path_join("build/rocks.json"), site.path_join("build/rocks_detected.json")]
	var before: Array = []
	for p in paths:
		before.append([FileAccess.get_modified_time(p), FileAccess.get_md5(p)])
	await seconds(1.1)  # file mtimes have 1 s resolution
	editor.select_at(Vector2(13.0, -20.0))
	editor.delete_selected()
	editor.add_rock(Vector2(0.0, 0.0), 4.0, 3.0, 10.0, 2.0)
	editor.save()
	for i in paths.size():
		check_eq([FileAccess.get_modified_time(paths[i]), FileAccess.get_md5(paths[i])], before[i],
			"%s untouched" % paths[i].get_file())


func test_select_mass_inside_outline(editor) -> void:
	check_eq(editor.select_at(Vector2(14.0, 24.0)), "fixtureC0003", "a point in the outline, far from the centre")
	check_eq(editor.select_at(Vector2(40.0, 40.0)), "", "empty ground selects nothing")
	check_eq(editor.selected_id, "", "selection cleared")


func test_height_change_is_a_changed_edit(editor) -> void:
	editor.select_at(Vector2(13.0, -20.0))
	editor.set_selected_height(3.0)
	editor.save()
	check_eq(_edits().get("changed", {}).get("fixtureB0002", {}), {"height": 3.0, "height_source": "shadow"},
		"changed entry")


func test_delete_added_rock_drops_it(editor) -> void:
	var id: String = editor.add_rock(Vector2(30.0, 30.0), 3.0, 2.0, 0.0, 1.0)
	check_eq(editor.select_at(Vector2(30.0, 30.0)), id, "select the added rock")
	editor.delete_selected()
	editor.save()
	var edits := _edits()
	check_eq(edits.get("added", []).size(), 0, "no longer added")
	check_eq(edits.get("deleted", []).size(), 0, "not recorded as a deletion")


func test_existing_edits_are_kept(editor) -> void:
	_write_edits({"added": [], "deleted": ["fixtureA0001"], "changed": {"fixtureC0003": {"height": 9.0}}})
	editor.load_site(site)
	check_eq(editor.rocks.size(), 2, "deleted rock hidden on load")
	editor.select_at(Vector2(13.0, -20.0))
	editor.delete_selected()
	editor.save()
	var edits := _edits()
	var deleted := Array(edits["deleted"])
	deleted.sort()
	check_eq(deleted, ["fixtureA0001", "fixtureB0002"], "both deletions")
	check_eq(edits["changed"], {"fixtureC0003": {"height": 9.0}}, "earlier change kept")


func test_added_footprint_height_and_unique_id(editor) -> void:
	var a: String = editor.add_rock(Vector2(-30.0, -30.0), 4.0, 2.5, 0.0, 0.0)
	var b: String = editor.add_rock(Vector2(-30.1, -30.1), 4.0, 2.5, 0.0, 0.0)
	check(a != b, "same 0.5 m cell still gets distinct ids")
	var r: Dictionary = editor.rock_by_id(a)
	check_eq(r["height_source"], "footprint", "no height given -> footprint rule")
	check_near(r["height"], 2.5 * RockEditor.FOOTPRINT_HEIGHT_RATIO, 0.01, "width x ratio")


func test_drag_geometry(_editor) -> void:
	var north: Dictionary = RockEditor.drag_rock(Vector2(0, 0), Vector2(0, -10), Vector2(1.5, -5))
	check_near(north["yaw_deg"], 0.0, 0.01, "drag north = yaw 0")
	check_near(north["length"], 10.0, 0.01, "length = drag length")
	check_near(north["width"], 3.0, 0.01, "width = 2 x offset from the axis")
	check_eq(north["pos"], Vector2(0, -5), "centre mid-drag")
	var east: Dictionary = RockEditor.drag_rock(Vector2(0, 0), Vector2(8, 0), Vector2(4, 1))
	check_near(east["yaw_deg"], 90.0, 0.01, "drag east = yaw 90")
	var wide: Dictionary = RockEditor.drag_rock(Vector2(0, 0), Vector2(8, 0), Vector2(4, 10))
	check_near(wide["length"], 20.0, 0.01, "wider than long -> axes swap")
	check_near(wide["width"], 8.0, 0.01, "short side")
	check_near(wide["yaw_deg"], 0.0, 0.01, "yaw follows the long axis")


func test_rock_id_matches_python(_editor) -> void:
	# replica.rocks.rock_id(10.1, -3.2) == sha1("10.0,-3.0")[:12]
	check_eq(RockEditor.rock_id(10.1, -3.2), "10.0,-3.0".sha1_text().substr(0, 12), "rounded key")
	check_eq(RockEditor.rock_id(0.25, 0.75), "0.0,1.0".sha1_text().substr(0, 12), "half to even like Python")


func test_site_arg(_editor) -> void:
	check_eq(RockEditor.site_from_args(PackedStringArray(["--only=x", "--site=data/sites/sumber"]), "D:/proj"),
		"D:/proj/data/sites/sumber", "relative to the project")
	check_eq(RockEditor.site_from_args(PackedStringArray(["--site=E:/s"]), "D:/proj"), "E:/s", "absolute kept")
	check_eq(RockEditor.site_from_args(PackedStringArray([]), "D:/proj"), "", "none")


func test_shadow_height(editor) -> void:
	check_near(editor.height_from_shadow(4.0), 4.0, 0.001, "tan 45 = 1 on the fixture sun")


func test_ortho_loaded(editor) -> void:
	check(editor.ortho_texture != null, "ortho loaded")
	if editor.ortho_texture:
		check_eq(editor.ortho_texture.get_size(), Vector2(200, 200), "fixture ortho size")
	check_eq(editor.rocks.size(), 3, "three rocks")
