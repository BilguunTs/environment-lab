class_name ReplicaGrass
extends Node3D
## Grass for a terrain replica: the project's GrassField (grass shader, wind, blade rules),
## streamed as TILE_M tiles around `target`, each tile's mask cut from the site's
## grass_density.png (one pixel per core sample: R = that density, 0-255 -> 0-1).
##
## A GrassField builds every blade of its extent at once and finds its ground by raycasts, which
## is fine for a playground meadow but not for 2 x 2 km; so tiles exist only within the blades'
## fade distance of the target (the blades are invisible beyond it anyway), at most one tile is
## made per frame, and a tile reads its ground heights from the terrain directly (Tile).
## Tile corners sit half a metre before a sample, so with texel_size 1 every texel centre is a
## core sample.

## Tile size (m). A performance choice: one tile's blades are built in one frame, and a 16 m tile
## of dense grass took over 1/60 s to build (Task 11 walk: 1 %-low 52-58 fps); 8 m keeps it under.
const TILE_M := 8
## Blades' height channel (G): halfway between BLADE_HEIGHT_M's ends.
const HEIGHT := 0.5
## Blade height range (m). The pipeline measures density only (a 0.8 m/px photo cannot see blade
## height), so this is the reference value for the vegetation, not a fit: the dry steppe of
## Govisumber (Stipa / Cleistogenes bunch grass) stands about 0.1-0.3 m in autumn.
const BLADE_HEIGHT_M := Vector2(0.1, 0.3)
## Blade colours: the imagery is from late October (Ruling 12), when the steppe grass is dry
## straw, so base and tip are the dry olive-tan of the GRASS ground colour, not the
## playground's green.
const BASE_COLOR := Color(0.24, 0.22, 0.13)
const TIP_COLOR := Color(0.58, 0.53, 0.36)

## Node the tiles follow (the player).
@export var target: Node3D

var _terrain: ReplicaTerrain
var _density := PackedByteArray()
var _n := 0
var _origin := 0.0
var _tiles := {}  # Vector2i -> Tile
var _keep_radius := 0.0


## `density`: n x n grey image (row 0 north), sample (i, j) at (origin + j, origin + i).
func setup(terrain: ReplicaTerrain, density: Image, origin: float) -> void:
	_terrain = terrain
	var image := density.duplicate() as Image
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	_density = image.get_data()
	_n = image.get_width()
	_origin = origin
	for tile: Node in _tiles.values():
		tile.queue_free()
	_tiles.clear()
	var probe := GrassField.new()
	_keep_radius = probe.fade_end + GrassField.CHUNK_SIZE
	probe.free()


func tile_count() -> int:
	return _tiles.size()


## Makes every tile the target needs right now (blocking; used at spawn).
func fill_now() -> void:
	while _step():
		pass


func _process(_delta: float) -> void:
	_step()


## Drops tiles out of range and makes the nearest missing one. False when none is missing.
func _step() -> bool:
	if target == null or _n == 0:
		return false
	var p := Vector2(target.global_position.x, target.global_position.z)
	for key: Vector2i in _tiles.keys():
		if _distance(key, p) > _keep_radius + TILE_M:
			_tiles[key].queue_free()
			_tiles.erase(key)
	var tiles_per_side := ceili(float(_n) / TILE_M)
	var reach := ceili(_keep_radius / TILE_M) + 1
	var centre := Vector2i(floori((p.x - _origin + 0.5) / TILE_M), floori((p.y - _origin + 0.5) / TILE_M))
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := centre + Vector2i(dx, dz)
			if key.x < 0 or key.y < 0 or key.x >= tiles_per_side or key.y >= tiles_per_side or _tiles.has(key):
				continue
			var d := _distance(key, p)
			if d <= _keep_radius and d < best_d:
				best = key
				best_d = d
	if best.x < 0:
		return false
	_make(best)
	return true


## Distance from p to the tile's rectangle.
func _distance(key: Vector2i, p: Vector2) -> float:
	var lo := Vector2(_origin - 0.5 + key.x * TILE_M, _origin - 0.5 + key.y * TILE_M)
	var q := p.clamp(lo, lo + Vector2(TILE_M, TILE_M))
	return q.distance_to(p)


func _make(key: Vector2i) -> void:
	var mask := PackedByteArray()
	mask.resize(TILE_M * TILE_M * 2)
	var g := clampi(roundi(HEIGHT * 255.0), 0, 255)
	var any := false
	for y in TILE_M:
		var i := key.y * TILE_M + y
		for x in TILE_M:
			var j := key.x * TILE_M + x
			var d := _density[i * _n + j] if i < _n and j < _n else 0
			mask[(y * TILE_M + x) * 2] = d
			mask[(y * TILE_M + x) * 2 + 1] = g
			any = any or d > 0
	var tile := Tile.new()
	tile.name = "Grass_%d_%d" % [key.x, key.y]
	tile.terrain = _terrain
	tile.texel_size = 1.0
	tile.extent = Vector2(TILE_M, TILE_M)
	tile.position = Vector3(_origin - 0.5 + (key.x + 0.5) * TILE_M, 0.0, _origin - 0.5 + (key.y + 0.5) * TILE_M)
	tile.min_height = BLADE_HEIGHT_M.x
	tile.max_height = BLADE_HEIGHT_M.y
	tile.base_color = BASE_COLOR
	tile.tip_color = TIP_COLOR
	tile.mask = Image.create_from_data(TILE_M, TILE_M, false, Image.FORMAT_RG8, mask)
	if not any:
		tile.blades_per_m2 = 0.0
	add_child(tile)
	# Build its blades now: left to GrassField's own _physics_process, every tile made since the
	# last physics tick (several per tick at a high frame rate) would build in that one tick.
	tile.rebuild()
	_tiles[key] = tile


## A GrassField whose ground comes from the replica terrain (exact, no raycasts).
class Tile extends GrassField:
	var terrain: ReplicaTerrain

	func _cache_ground() -> void:
		var size := mask_size()
		_ground.resize(size.x * size.y)
		_ground_size = size
		_ground_origin = global_position
		_ground_valid = true
		var corner := _corner()
		for y in size.y:
			for x in size.x:
				var p := corner + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel_size
				_ground[y * size.x + x] = terrain.height_at(p.x, p.y)
