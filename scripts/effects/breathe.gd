class_name Breathe
extends MeshInstance3D
## Slow, even pulse for supernatural light: fire flickers, spirits breathe.
## Drives this mesh's emission, an optional light and an optional halo from one intensity value.

@export_range(0.0, 2.0) var intensity := 1.0
@export var base_emission := 14.0
@export var light: Light3D
@export var base_light_energy := 4.0
## Billboard with a light_halo material; its "energy" pulses with the core.
@export var halo: MeshInstance3D
@export var base_halo_energy := 1.5
@export_range(0.0, 1.0) var amount := 0.3
@export var period := 6.0

var _t := 0.0
var _mat: StandardMaterial3D
var _halo_mat: ShaderMaterial


func _ready() -> void:
	_mat = material_override.duplicate()
	material_override = _mat
	if halo:
		_halo_mat = halo.material_override


func _process(delta: float) -> void:
	_t += delta
	# Ease-in-out breath rather than a plain sine: a longer rest at the bottom of the cycle.
	var breath := pow(0.5 - 0.5 * cos(TAU * _t / period), 1.5)
	var k := intensity * (1.0 - amount + amount * 2.0 * breath)
	_mat.emission_energy_multiplier = base_emission * k
	if light:
		light.light_energy = base_light_energy * k
	if _halo_mat:
		_halo_mat.set_shader_parameter("energy", base_halo_energy * k)
