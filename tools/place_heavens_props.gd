extends SceneTree
## One-off staging helper for Heavens call (Task 5). The tables below are the hand-authored
## placement: every prop is given as (progress along the trail, metres right (+) or left (-) of
## the centreline, yaw relative to the walking direction, sink, scale, how much it leans with the
## ground). This script only resolves the ground height and slope under each prop and prints the
## `Debris`, `Traces` and `Rocks` nodes as .tscn text with plain baked transforms, which were
## pasted into scenes/levels/heavens_call.tscn. Every piece gets height_from_origin = true
## (kit_asset.gd), since the mountain is far above y = 0. The scene is the source of truth;
## re-run only to re-stage from scratch:
##   Godot --headless --path . -s res://tools/place_heavens_props.gd > out.txt

const KIT := "res://scenes/environment/kit/"
## Scene file per kind, with the ext_resource id it gets in heavens_call.tscn.
const KINDS := {
	"shield": ["prop_shield_broken", "12"],
	"sword": ["prop_sword_planted", "13"],
	"helmet": ["prop_helmet", "14"],
	"breastplate": ["prop_breastplate", "15"],
	"spear": ["prop_spear_broken", "16"],
	"scarf": ["prop_scarf_worn", "17"],
	"cairn": ["prop_cairn", "18"],
	"fire": ["prop_fire_ring", "19"],
	"boulder_a": ["rock_boulder_a", "20"],
	"boulder_b": ["rock_boulder_b", "21"],
	"shard": ["rock_shard", "22"],
}

# kind, progress, lateral m (+ right), yaw deg, sink m, scale, align with the ground (0..1)
const DEBRIS := [
	# The first sign: one sword planted by the path, a helmet behind it.
	["sword", 0.287, -3.4, 20, 0.0, 1.0, 0.3],
	["helmet", 0.292, -4.6, 140, 0.03, 1.0, 1.0],
	# A shield and a snapped spear at the right edge, a helmet half sunk beyond.
	["shield", 0.318, 3.6, 30, 0.02, 1.0, 1.0],
	["spear", 0.323, 2.5, 80, 0.01, 1.0, 1.0],
	["helmet", 0.327, 5.2, 250, 0.06, 1.0, 1.0],
	# Under the uphill wall.
	["breastplate", 0.352, -4.2, 75, 0.01, 1.0, 1.0],
	["sword", 0.357, -5.8, 200, 0.05, 1.0, 0.3],
	["shield", 0.361, -3.0, 160, 0.07, 1.0, 1.0],
	# The narrows at 0.40: where they held the pass. The densest cluster, both sides.
	["breastplate", 0.386, -2.6, 300, 0.02, 1.0, 1.0],
	["shield", 0.391, 2.7, 210, 0.02, 1.0, 1.0],
	["helmet", 0.396, -2.3, 30, 0.02, 1.0, 1.0],
	["sword", 0.394, 3.8, 250, 0.03, 1.0, 0.3],
	["sword", 0.399, 3.1, 160, 0.0, 1.0, 0.3],
	["spear", 0.403, 2.3, 95, 0.01, 1.0, 1.0],
	["sword", 0.405, -3.0, 340, 0.1, 1.0, 0.3],
	["sword", 0.409, -3.5, 120, 0.05, 1.0, 0.3],
	["shield", 0.412, -2.6, 100, 0.08, 1.0, 1.0],
	# A ledge above the drop, on the right.
	["helmet", 0.438, 6.4, 60, 0.03, 1.0, 1.0],
	["sword", 0.443, 7.6, 100, 0.0, 1.0, 0.3],
	["spear", 0.447, 5.4, 140, 0.01, 1.0, 1.0],
	# Strays before the corner.
	["shield", 0.484, 4.0, 290, 0.03, 1.0, 1.0],
	["breastplate", 0.494, 3.2, 20, 0.02, 1.0, 1.0],
	# The flat landing at the switchback.
	["sword", 0.514, 4.6, 230, 0.0, 1.0, 0.3],
	["helmet", 0.518, 3.0, 300, 0.02, 1.0, 1.0],
	["spear", 0.521, -3.2, 200, 0.01, 1.0, 1.0],
	["shield", 0.525, 6.0, 20, 0.1, 1.0, 1.0],
	# The last of it, thinning out.
	["sword", 0.561, -4.2, 70, 0.04, 1.0, 0.3],
	["helmet", 0.578, 3.6, 190, 0.05, 1.0, 1.0],
]

const TRACES := [
	["cairn", 0.615, -4.0, 0, 0.0, 0.6, 0.0],
	["scarf", 0.662, 4.2, 70, 0.04, 1.0, 0.0],
	["cairn", 0.703, 3.6, 40, 0.0, 0.75, 0.0],
	# The sheltered ledge under the wall: a cold hearth, a small stack beside it.
	["fire", 0.752, -4.8, 0, 0.02, 1.0, 1.0],
	["cairn", 0.757, -6.4, 0, 0.0, 0.55, 0.0],
	["cairn", 0.792, -4.4, 120, 0.0, 0.8, 0.0],
	["scarf", 0.832, 3.0, 200, 0.04, 1.0, 0.0],
	["cairn", 0.878, 4.0, 200, 0.0, 0.7, 0.0],
	["cairn", 0.934, -3.4, 80, 0.0, 0.9, 0.0],
]

# kind, progress, lateral, scale: against the walls, on ledge lips, beside the debris.
const ROCKS := [
	["boulder_a", 0.02, -6.5, 1.2], ["shard", 0.024, -7.8, 0.8],
	["boulder_b", 0.045, 6.0, 0.9],
	["boulder_a", 0.075, -7.0, 1.0], ["boulder_b", 0.079, -5.6, 0.6],
	["shard", 0.11, 6.8, 0.7],
	["boulder_a", 0.14, 6.2, 0.8], ["boulder_b", 0.145, 7.4, 1.1],
	["boulder_a", 0.175, -4.8, 0.9], ["shard", 0.186, -4.4, 0.6],
	["boulder_b", 0.215, 6.4, 1.0],
	["boulder_a", 0.25, -6.0, 1.3], ["shard", 0.255, -7.5, 1.0],
	["boulder_b", 0.275, 5.8, 0.7],
	["boulder_a", 0.30, -5.6, 1.1],
	["boulder_b", 0.33, 6.6, 0.8],
	["boulder_a", 0.366, -7.6, 1.0],
	["boulder_a", 0.389, 4.9, 0.9], ["shard", 0.40, -4.7, 0.9],
	["boulder_b", 0.416, 4.5, 0.7],
	["boulder_a", 0.452, 8.4, 0.8],
	["shard", 0.47, -6.6, 0.9],
	["boulder_b", 0.50, 5.8, 1.0],
	["boulder_a", 0.53, 7.0, 1.2],
	["shard", 0.55, 7.0, 1.1],
	["boulder_a", 0.585, 6.8, 1.0], ["boulder_b", 0.589, -5.8, 0.7],
	["shard", 0.62, 7.2, 0.9],
	["boulder_a", 0.645, -6.6, 1.1],
	["boulder_b", 0.68, -6.0, 0.8],
	["boulder_a", 0.725, -6.4, 1.0],
	["shard", 0.745, -7.3, 1.2],
	["boulder_b", 0.77, 6.2, 0.9],
	["boulder_a", 0.80, -6.8, 1.0],
	["shard", 0.815, -4.6, 0.8],
	["boulder_b", 0.845, 6.0, 1.0],
	["boulder_a", 0.87, -6.4, 1.2],
	["shard", 0.90, 6.6, 0.8],
	["boulder_b", 0.925, -6.2, 0.9],
	["boulder_a", 0.955, 7.0, 0.9],
]

var _trail: Trail
var _terrain: MountainTerrain


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lv: Node3D = load("res://scenes/levels/heavens_call.tscn").instantiate()
	root.add_child(lv)
	await process_frame
	_trail = lv.get_node("Trail")
	_terrain = lv.get_node("MountainTerrain")
	var out := ""
	for kind: String in KINDS:
		out += '[ext_resource type="PackedScene" path="%s%s.tscn" id="%s"]\n' % [KIT, KINDS[kind][0], KINDS[kind][1]]
	out += "\n"
	out += _group("Debris", DEBRIS)
	out += _group("Traces", TRACES)
	var rocks := []
	for i in ROCKS.size():
		var r: Array = ROCKS[i]
		# Rocks: yaw by the golden angle, sunk by their size, half leaning with the slope.
		rocks.append([r[0], r[1], r[2], fmod(i * 137.5, 360.0), 0.15 * r[3], r[3], 0.5])
	out += _group("Rocks", rocks)
	print("=====BEGIN=====")
	print(out)
	print("=====END=====")
	quit()


func _group(group: String, rows: Array) -> String:
	var s := '[node name="%s" type="Node3D" parent="."]\n\n' % group
	var counts := {}
	for row: Array in rows:
		var kind: String = row[0]
		counts[kind] = counts.get(kind, 0) + 1
		var xf := _place(row)
		var name := "%s%d" % [kind.capitalize().replace(" ", ""), counts[kind]]
		s += '[node name="%s" parent="%s" instance=ExtResource("%s")]\n' % [name, group, KINDS[kind][1]]
		s += "transform = %s\n" % var_to_str(xf)
		s += "height_from_origin = true\n\n"  # sway and shade from its own origin, not y = 0
		printerr("%s/%s progress %.3f -> %.3f, %.1f m from centre" % [group, name, row[1],
				_trail.progress_at(xf.origin), _trail.distance_to_centre(xf.origin)])
	return s


func _place(row: Array) -> Transform3D:
	var progress: float = row[1]
	var lateral: float = row[2]
	var c := _trail.point_at(progress)
	var ahead := _trail.point_at(minf(progress + 0.003, 1.0)) - _trail.point_at(maxf(progress - 0.003, 0.0))
	ahead.y = 0.0
	ahead = ahead.normalized()
	var right := ahead.cross(Vector3.UP).normalized()
	var p := c + right * lateral
	var xz := Vector2(p.x, p.z)
	p.y = _terrain.height_at(xz) - float(row[4])
	var e := 0.35
	var n := Vector3(_terrain.height_at(xz - Vector2(e, 0)) - _terrain.height_at(xz + Vector2(e, 0)), 2.0 * e,
			_terrain.height_at(xz - Vector2(0, e)) - _terrain.height_at(xz + Vector2(0, e))).normalized()
	var up := Vector3.UP.lerp(n, float(row[6])).normalized()
	var heading := atan2(ahead.x, ahead.z)
	var basis := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, heading + deg_to_rad(float(row[3])))
	basis = basis.scaled_local(Vector3.ONE * float(row[5]))
	return Transform3D(basis, p)
