@tool
class_name Scatter
extends Node3D
## Reproducible scatter of scenes over a rectangle centred on this node.
##
## Each candidate point draws all of its random numbers up front, then is kept with a
## probability shaped by: a clumping noise (groves and gaps), distance from the path,
## ExclusionZones, and spacing to already placed items and hand-placed obstacles.
## Same seed + same parameters = the same result. Because the random sequence never
## shifts, a small parameter change gives a small change in the result.
##
## Generated nodes are not saved with the scene: hide the node (or switch the forest mode)
## and they are gone. Runs in the editor too, so parameters can be tuned live.

signal generated(count: int)

@export var random_seed := 1:
	set(v):
		if v != random_seed:
			random_seed = v
			mark_dirty()
## Offsets the random_seed so several layers sharing one seed still differ.
@export var salt := 0
@export var extent := Vector2(74, 104):
	set(v):
		extent = v
		mark_dirty()
## Candidate points per 100 m² before any masking. More candidates also fill gaps up to min_spacing.
@export_range(0.0, 20.0, 0.1) var density := 4.5:
	set(v):
		if not is_equal_approx(v, density):
			density = v
			mark_dirty()
@export_range(0.5, 20.0, 0.1) var min_spacing := 3.4:
	set(v):
		if not is_equal_approx(v, min_spacing):
			min_spacing = v
			mark_dirty()
## 0 = even coverage, 1 = strongly grouped into groves with open gaps.
@export_range(0.0, 1.0, 0.01) var clumping := 0.55:
	set(v):
		if not is_equal_approx(v, clumping):
			clumping = v
			mark_dirty()
## Rough distance between grove centres (noise wavelength), metres.
@export var clump_size := 24.0:
	set(v):
		clump_size = v
		mark_dirty()

@export_group("Items")
@export var scenes: Array[PackedScene] = []:
	set(v):
		scenes = v
		mark_dirty()
## Relative pick weight per scene (missing entries count as 1).
@export var weights := PackedFloat32Array():
	set(v):
		weights = v
		mark_dirty()
@export var scale_range := Vector2(0.8, 1.3)
@export_range(0.0, 30.0) var max_tilt_deg := 0.0
@export var name_prefix := "Item"

@export_group("Masks")
## path_ribbon.gd nodes; items keep clear of all of them.
@export var paths: Array[NodePath] = []
## Clear distance from the path edge.
@export var path_margin := 4.0
## Distance beyond the margin over which items fade back in.
@export var path_falloff := 3.0
## Density stays full next to the path and fades to `far_keep` by `far_distance` metres away:
## walls of trees frame the corridor, the deep forest is thinner. far_keep = 1 disables it.
@export var far_distance := 20.0
@export_range(0.0, 1.0, 0.01) var far_keep := 1.0
## Parent of ExclusionZone nodes.
@export var zones_root: NodePath
## Children of these nodes are treated as hand-placed obstacles (kept `obstacle_radius` clear).
@export var obstacle_roots: Array[NodePath] = []
@export var obstacle_radius := 2.5

@export_group("Ground")
## Items drop onto collision found below them on `ground_layer`; otherwise y = 0.
@export var snap_to_ground := true
## Static bodies under these nodes are added to `ground_layer` so the snap ray can find them.
@export var ground_roots: Array[NodePath] = []
@export_range(1, 32) var ground_layer := 2

var count := 0
var _dirty := true


func _ready() -> void:
	visibility_changed.connect(mark_dirty)


func mark_dirty() -> void:
	_dirty = true


# Generate inside the physics step: that's where the space state is safe to raycast.
func _physics_process(_delta: float) -> void:
	if _dirty and is_inside_tree():
		_dirty = false
		generate()


func generate() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	count = 0
	if not is_visible_in_tree() or scenes.is_empty():
		generated.emit(0)
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash([random_seed, salt])
	var noise := FastNoiseLite.new()
	noise.seed = random_seed * 7919 + salt
	noise.frequency = 1.0 / maxf(clump_size, 1.0)
	var path_lines := _path_lines()
	var zones := _zones()
	var obstacles := _obstacle_points()
	var total_weight := 0.0
	for i in scenes.size():
		total_weight += _weight_of(i)

	var origin := global_position
	var candidates := int(extent.x * extent.y * density / 100.0)
	var grid := {}  # Vector2i -> Array of Vector2, for spacing checks
	var placed: Array[Dictionary] = []
	for i in candidates:
		var p := Vector2(origin.x + (rng.randf() - 0.5) * extent.x, origin.z + (rng.randf() - 0.5) * extent.y)
		var keep := rng.randf()
		var pick := rng.randf() * total_weight
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var yaw := rng.randf() * TAU
		var tilt := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * deg_to_rad(max_tilt_deg)

		if keep > _mask(p, noise, path_lines, zones):
			continue
		if _near(p, obstacles, obstacle_radius) or _crowded(p, grid):
			continue
		var cell := Vector2i((p / min_spacing).floor())
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(p)
		placed.append({"p": p, "scene": _pick(pick), "scale": s, "yaw": yaw, "tilt": tilt})

	# Ground heights first, before any new colliders exist to get in the way.
	var heights := _ground_heights(placed)
	for i in placed.size():
		var item: Dictionary = placed[i]
		var node: Node3D = scenes[item.scene].instantiate()
		node.name = "%s%03d" % [name_prefix, i]
		add_child(node)
		var rot := Basis(Vector3.UP, item.yaw) * Basis.from_euler(Vector3(item.tilt.x, 0, item.tilt.y))
		node.global_transform = Transform3D(rot.scaled(Vector3.ONE * item.scale),
				Vector3(item.p.x, heights[i], item.p.y))
	count = placed.size()
	generated.emit(count)


# --- masks ------------------------------------------------------------------------------

## Probability (0..1) of keeping an item at p.
func _mask(p: Vector2, noise: FastNoiseLite, path_lines: Array, zones: Array) -> float:
	var w := 1.0
	if clumping > 0.0:
		var n := noise.get_noise_2d(p.x, p.y)  # roughly -0.6..0.6
		w *= lerpf(1.0, smoothstep(-0.2, 0.3, n), clumping)
	if not path_lines.is_empty():
		var d := INF
		for line: Array in path_lines:
			d = minf(d, _distance_to_polyline(p, line[0]) - line[1])
		if d < path_margin:
			return 0.0
		if path_falloff > 0.0:
			w *= clampf((d - path_margin) / path_falloff, 0.0, 1.0)
		if far_keep < 1.0:
			w *= lerpf(1.0, far_keep, smoothstep(path_margin, far_distance, d))
	for zone: ExclusionZone in zones:
		w *= zone.weight(Vector3(p.x, 0.0, p.y))
		if w <= 0.0:
			return 0.0
	return w


func _crowded(p: Vector2, grid: Dictionary) -> bool:
	var c := Vector2i((p / min_spacing).floor())
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for q: Vector2 in grid.get(Vector2i(x, y), []):
				if p.distance_squared_to(q) < min_spacing * min_spacing:
					return true
	return false


static func _near(p: Vector2, points: PackedVector2Array, radius: float) -> bool:
	for q in points:
		if p.distance_squared_to(q) < radius * radius:
			return true
	return false


static func _distance_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func _pick(r: float) -> int:
	for i in scenes.size():
		r -= _weight_of(i)
		if r <= 0.0:
			return i
	return scenes.size() - 1


func _weight_of(i: int) -> float:
	return weights[i] if i < weights.size() else 1.0


# --- inputs from the scene ----------------------------------------------------------------

## [[centre line, half width], ...] for every assigned path.
func _path_lines() -> Array:
	var out := []
	for np in paths:
		var node := get_node_or_null(np)
		if node and node.has_method("get_centerline_world"):
			var pts: PackedVector2Array = node.get_centerline_world()
			if pts.size() >= 2:
				out.append([pts, node.width * 0.5])
	return out


func _zones() -> Array:
	var out := []
	var root := get_node_or_null(zones_root)
	if root:
		for child in root.get_children():
			if child is ExclusionZone:
				out.append(child)
	return out


func _obstacle_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for np in obstacle_roots:
		var root := get_node_or_null(np)
		if root:
			for child in root.get_children():
				if child is Node3D:
					out.append(Vector2(child.global_position.x, child.global_position.z))
	return out


func _ground_heights(placed: Array[Dictionary]) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(placed.size())
	heights.fill(0.0)
	if not snap_to_ground or placed.is_empty():
		return heights
	for np in ground_roots:
		var root := get_node_or_null(np)
		if root:
			_tag_ground(root)
	var space := get_world_3d().direct_space_state
	if space == null:
		return heights
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1 << (ground_layer - 1)
	for i in placed.size():
		var p: Vector2 = placed[i].p
		query.from = Vector3(p.x, 40.0, p.y)
		query.to = Vector3(p.x, -5.0, p.y)
		var hit := space.intersect_ray(query)
		if hit:
			heights[i] = hit.position.y
	return heights


func _tag_ground(node: Node) -> void:
	if node is CollisionObject3D:
		node.set_collision_layer_value(ground_layer, true)
	for child in node.get_children():
		_tag_ground(child)
