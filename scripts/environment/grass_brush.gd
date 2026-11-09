class_name GrassBrush
extends RefCounted
## One brush stroke on a GrassField's mask: begin() snapshots the mask, dab() paints a disc and
## rebuilds only the chunks it touched, end() hands back the [before, after] pair for undo.
##
## Holds the testable logic of the grass painter (addons/grass_painter), which is glue only.

var mode := GrassField.PaintMode.DENSITY
## Brush radius in metres.
var radius := 3.0
## How far one dab moves a texel toward the target (0..1).
var strength := 0.3
## Density or height the brush paints toward (0..1); ignored when erasing.
var target := 1.0
## Fraction of the radius over which the dab fades out at its rim.
var falloff := 0.5

const RAY_LENGTH := 2000.0

var _field: GrassField
var _before: Image
var _last_dab := Vector3.INF


## Starts a stroke on `field`, remembering its mask for undo.
func begin(field: GrassField) -> void:
	_field = field
	field.ensure_mask()
	_before = field.mask.duplicate()
	_last_dab = Vector3.INF


## Paints one dab at `world_pos`. Skipped if it is within radius * 0.25 of the stroke's last
## dab, so a slow drag doesn't pile dabs on one spot.
func dab(world_pos: Vector3) -> void:
	if _field == null or not is_instance_valid(_field):
		return
	if _last_dab != Vector3.INF and world_pos.distance_to(_last_dab) < radius * 0.25:
		return
	_last_dab = world_pos
	var rect := _field.paint(world_pos, radius, mode, target, strength, falloff)
	if rect.has_area():  # an empty rect would mean "rebuild everything"
		_field.rebuild(rect)


## True between begin() and end().
func is_painting() -> bool:
	return _field != null


## Ends the stroke and returns [before, after] copies of the mask; empty if no stroke was open.
func end() -> Array[Image]:
	var pair: Array[Image] = []
	if _field != null and is_instance_valid(_field) and _before != null:
		pair = [_before, _field.mask.duplicate()]
	_field = null
	_before = null
	_last_dab = Vector3.INF
	return pair


## Where a ray from `from` along `dir` hits `field.ground_layer`, or null.
static func ray_to_ground(field: GrassField, from: Vector3, dir: Vector3) -> Variant:
	if not field.is_inside_tree() or dir.is_zero_approx():
		return null
	var space := field.get_world_3d().direct_space_state
	if space == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * RAY_LENGTH,
			1 << (field.ground_layer - 1))
	var hit := space.intersect_ray(query)
	return hit.position if hit else null


## True when painting `mask` in the scene saved at `scene_path` would overwrite a mask another
## field or scene owns, so the painter must paint a copy (saved as <scene>_grass[_N].res) instead:
## another GrassField of the scene holds the same mask (`other_masks`, e.g. after Ctrl+D), or the
## mask's file isn't this scene's (named <scene>_grass*, in any folder, or embedded in the scene).
static func mask_needs_fork(mask: Image, scene_path: String, other_masks: Array) -> bool:
	if mask == null:
		return false
	for other in other_masks:
		if is_same(other, mask):
			return true
	var path := mask.resource_path
	if path.is_empty() or scene_path.is_empty():
		return false  # unsaved mask (the painter saves it next to the scene), or unknown scene
	if path.contains("::"):
		return path.get_slice("::", 0) != scene_path
	return not path.get_file().begins_with(scene_path.get_file().get_basename() + "_grass")
