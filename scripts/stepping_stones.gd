extends Node3D
## Заросшая дорожка из каменных плиток. Плитки лежат под травой
## и показываются, когда её скашивают.

## Начало и конец дорожки в координатах узла.
@export var from := Vector3(0.0, 0.0, 5.0)
@export var to := Vector3(0.0, 0.0, -5.0)
@export var count := 8
## Насколько плитки отклоняются от прямой, в метрах.
@export var wobble := 0.22
@export var stone_radius := 0.4
@export var random_seed := 3

const STONES := [Color(0.74, 0.73, 0.72), Color(0.66, 0.66, 0.68), Color(0.80, 0.78, 0.74)]

var _positions := PackedVector3Array()


func _enter_tree() -> void:
	add_to_group("grass_shaper")
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var side := (to - from).cross(Vector3.UP).normalized()
	_positions.clear()
	for i in count:
		var along := from.lerp(to, float(i) / maxi(count - 1, 1))
		var sway := wobble * (1.0 if i % 2 == 0 else -1.0) + rng.randf_range(-0.08, 0.08)
		_positions.append(along + side * sway)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for at in _positions:
		var radius := stone_radius * rng.randf_range(0.85, 1.1)
		var stone := Placeholder.part(self, Placeholder.cylinder(radius, 0.07, radius * 0.9),
				STONES[rng.randi() % STONES.size()], at + Vector3(0.0, 0.035, 0.0))
		stone.rotation.y = rng.randf() * TAU
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func shape_grass(field: MowField) -> void:
	for at in _positions:
		field.pave_circle(to_global(at), stone_radius + 0.08)
