class_name FlowerBed
extends Interactable
## Заросшая клумба. Находится под травой; когда её выкосили, можно
## посадить цветы за компост. Цветы распускаются сразу, без ожидания.

## Уникальный идентификатор для сохранения.
@export var bed_id := ""
## Размер клумбы в метрах (X, Z).
@export var bed_size := Vector2(2.0, 0.9)
@export var compost_cost := 5

const STONE := Color(0.76, 0.74, 0.72)
const SOIL := Color(0.50, 0.38, 0.27)
const STEM := Color(0.30, 0.62, 0.30)
const CENTER := Color(1.0, 0.85, 0.3)
const PETALS := [
	Color(1.0, 0.55, 0.65), Color(1.0, 0.86, 0.35), Color(0.98, 0.97, 0.94),
	Color(0.72, 0.58, 1.0), Color(1.0, 0.62, 0.32),
]
## На каком расстоянии от косилки цветы приминаются.
const PRESS_RADIUS := 0.7

var _field: MowField
var _revealed := false
var _planted := false
var _time := 0.0
## Внутренние узлы цветов: их качает ветер и приминает косилка.
var _stems: Array[Node3D] = []


func _enter_tree() -> void:
	super()
	add_to_group("grass_shaper")
	add_to_group("flower_bed")


func _ready() -> void:
	_field = get_tree().get_first_node_in_group("mow_field") as MowField
	# Расстояние меряется от центра, поэтому длинной клумбе нужен радиус побольше.
	interact_radius = 1.2 + maxf(bed_size.x, bed_size.y) * 0.5
	_build_border()
	if GameState.has_flag(_flag()):
		_revealed = true
		_plant(false)


func _process(delta: float) -> void:
	_time += delta
	if not _revealed:
		if _is_uncovered():
			_reveal()
		return
	if not _planted:
		return

	var mower := Vector3(INF, 0.0, INF)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		mower = player.global_position - player.global_basis.z * 0.95
	for i in _stems.size():
		var stem := _stems[i]
		var offset := stem.global_position - mower
		offset.y = 0.0
		var press := clampf(1.0 - offset.length() / PRESS_RADIUS, 0.0, 1.0)
		stem.scale.y = lerpf(stem.scale.y, 1.0 - 0.65 * press, 1.0 - exp(-14.0 * delta))
		stem.rotation.z = sin(_time * 1.6 + i * 1.3) * 0.09


func is_planted() -> bool:
	return _planted


func shape_grass(field: MowField) -> void:
	field.pave_rect(global_position, bed_size + Vector2(0.25, 0.25), global_rotation.y)


func get_prompt() -> String:
	return "Посадить цветы — %d компоста" % compost_cost


func can_interact(_player: Player) -> bool:
	return _revealed and not _planted


func interact(_player: Player) -> void:
	if not GameState.spend_compost(compost_cost):
		Sfx.play("deny")
		GameState.toast("Не хватает компоста: нужно %d. Скосите траву и отвезите её в ящик" % compost_cost)
		return
	GameState.set_flag(_flag())
	_plant(true)
	GameState.save_game()


func _is_uncovered() -> bool:
	if _field == null:
		return false
	var half := bed_size * 0.4
	for corner: Vector2 in [Vector2.ZERO, half, -half, Vector2(half.x, -half.y), Vector2(-half.x, half.y)]:
		if _field.get_height_at(to_global(Vector3(corner.x, 0.0, corner.y))) > 0.0:
			return false
	return true


func _reveal() -> void:
	_revealed = true
	Juice.sparkle(self, global_position + Vector3.UP * 0.4)
	Sfx.play("pop")
	if not GameState.has_flag("hint_flower_bed"):
		GameState.set_flag("hint_flower_bed")
		GameState.toast("Клумба! Здесь можно посадить цветы за компост")


func _plant(animated: bool) -> void:
	_planted = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bed_id)
	var columns := maxi(int(bed_size.x / 0.38), 1)
	var rows := maxi(int(bed_size.y / 0.36), 1)
	var index := 0
	for row in rows:
		for column in columns:
			var at := Vector3(
					((column + 0.5) / columns - 0.5) * bed_size.x + rng.randf_range(-0.07, 0.07),
					0.0,
					((row + 0.5) / rows - 0.5) * bed_size.y + rng.randf_range(-0.07, 0.07))
			var flower := _create_flower(rng)
			flower.position = at
			flower.rotation.y = rng.randf() * TAU
			add_child(flower)
			if animated:
				# Цветы выскакивают один за другим.
				flower.scale = Vector3.ONE * 0.01
				var tween := flower.create_tween()
				tween.tween_interval(0.07 * index)
				tween.tween_property(flower, "scale", Vector3.ONE, 0.45) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			index += 1

	for i in 2:
		var butterfly := Butterfly.new()
		butterfly.color = PETALS[(rng.randi() + i) % PETALS.size()]
		butterfly.roam_radius = maxf(bed_size.x, bed_size.y) * 0.55
		add_child(butterfly)

	if animated:
		Sfx.play("plant")
		Sfx.buzz(25)
		Juice.sparkle(self, global_position + Vector3.UP * 0.5, Color(1.0, 0.8, 0.9), 26)


func _create_flower(rng: RandomNumberGenerator) -> Node3D:
	var flower := Node3D.new()
	var stem := Node3D.new()
	flower.add_child(stem)
	_stems.append(stem)
	var height := rng.randf_range(0.32, 0.55)
	var petal: Color = PETALS[rng.randi() % PETALS.size()]
	Placeholder.part(stem, Placeholder.cylinder(0.025, height), STEM, Vector3(0.0, height * 0.5, 0.0))
	Placeholder.part(stem, Placeholder.sphere(0.06), STEM, Vector3(0.06, height * 0.4, 0.0))
	var head := Placeholder.part(stem, Placeholder.sphere(0.13), petal, Vector3(0.0, height, 0.0))
	head.scale = Vector3(1.0, 0.55, 1.0)
	Placeholder.part(stem, Placeholder.sphere(0.06), CENTER, Vector3(0.0, height + 0.05, 0.0))
	return flower


func _build_border() -> void:
	# Земля чуть приподнята, по краю — камешки.
	var soil := Placeholder.part(self, Placeholder.box(Vector3(bed_size.x, 0.08, bed_size.y)), SOIL,
			Vector3(0.0, 0.03, 0.0))
	soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bed_id) + 1
	var half := bed_size * 0.5
	var perimeter := (bed_size.x + bed_size.y) * 2.0
	var count := int(perimeter / 0.3)
	for i in count:
		var along := perimeter * i / count
		var at: Vector2
		if along < bed_size.x:
			at = Vector2(-half.x + along, -half.y)
		elif along < bed_size.x + bed_size.y:
			at = Vector2(half.x, -half.y + (along - bed_size.x))
		elif along < bed_size.x * 2.0 + bed_size.y:
			at = Vector2(half.x - (along - bed_size.x - bed_size.y), half.y)
		else:
			at = Vector2(-half.x, half.y - (along - bed_size.x * 2.0 - bed_size.y))
		var pebble := Placeholder.part(self, Placeholder.sphere(rng.randf_range(0.1, 0.14)), STONE,
				Vector3(at.x, 0.05, at.y))
		pebble.scale = Vector3(1.0, 0.7, 1.0)


func _flag() -> String:
	return "bed_" + bed_id
