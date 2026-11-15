class_name FlowerBed
extends Interactable
## Заросшая клумба. Находится под травой; когда её выкосили, можно
## посадить цветы за компост. Цветы распускаются сразу, без ожидания.

## Уникальный идентификатор для сохранения.
@export var bed_id := ""
## Размер клумбы в метрах (X, Z).
@export var bed_size := Vector2(2.0, 0.9)
@export var compost_cost := 5

const SOIL := Color(0.50, 0.38, 0.27)
const TALL_FLOWERS := ["flowers_tall", "flowers_tall_yellow", "flowers_tall_pink"]
const LOW_FLOWERS := ["flowers_low", "flowers_low_white", "flowers_low_violet"]
const PETALS := [
	Color(1.0, 0.55, 0.65), Color(1.0, 0.86, 0.35), Color(0.98, 0.97, 0.94),
	Color(0.72, 0.58, 1.0), Color(1.0, 0.62, 0.32),
]

var _field: MowField
var _revealed := false
var _planted := false


func _enter_tree() -> void:
	super()
	add_to_group("grass_shaper")
	add_to_group("flower_bed")


func _ready() -> void:
	var plot := Plot.of(self)
	_field = plot.field if plot else get_tree().get_first_node_in_group("mow_field") as MowField
	# Расстояние меряется от центра, поэтому длинной клумбе нужен радиус побольше.
	interact_radius = 1.2 + maxf(bed_size.x, bed_size.y) * 0.5
	_build_border()
	if GameState.has_flag(_flag()):
		_revealed = true
		_plant(false)


func _process(_delta: float) -> void:
	# Цветы качаются и приминаются косилкой в шейдере (toon_plant);
	# здесь остаётся только ждать, пока клумбу выкосят.
	if not _revealed and _is_uncovered():
		_reveal()


func is_planted() -> bool:
	return _planted


func shape_grass(field: MowField) -> void:
	field.pave_rect(global_position, bed_size + Vector2(0.25, 0.25), global_rotation.y)


func get_prompt() -> String:
	return L.t("Посадить цветы — %d компоста") % compost_cost


func can_interact(_player: Player) -> bool:
	return _revealed and not _planted


func interact(_player: Player) -> void:
	if not GameState.spend_compost(compost_cost):
		Sfx.play("deny")
		GameState.toast(L.t("Не хватает компоста: нужно %d. Скосите траву и отвезите её в ящик") % compost_cost)
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
	set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bed_id)
	# Все цветы клумбы — одна модель (Placeholder.bake_tree).
	var flowers := Node3D.new()
	flowers.name = "Flowers"
	flowers.set_meta("plant", true)
	add_child(flowers)
	# Цветы — кустики из Kenney Platformer Kit: высокие в три цвета и между
	# ними низкие.
	var columns := maxi(int(bed_size.x / 0.5), 1)
	var rows := maxi(int(bed_size.y / 0.45), 1)
	for row in rows:
		for column in columns:
			var at := Vector3(
					((column + 0.5) / columns - 0.5) * bed_size.x + rng.randf_range(-0.05, 0.05),
					0.04,
					((row + 0.5) / rows - 0.5) * bed_size.y + rng.randf_range(-0.05, 0.05))
			Models.place(flowers, TALL_FLOWERS[rng.randi() % TALL_FLOWERS.size()], at,
					rng.randf_range(0.8, 1.05), rng.randf() * TAU, false)
			if rng.randf() < 0.6:
				var beside := at + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.18, 0.18))
				Models.place(flowers, LOW_FLOWERS[rng.randi() % LOW_FLOWERS.size()], beside,
						rng.randf_range(0.45, 0.6), rng.randf() * TAU, false)
	Placeholder.bake_tree(flowers)

	for i in 2:
		var butterfly := Butterfly.new()
		butterfly.color = PETALS[(rng.randi() + i) % PETALS.size()]
		butterfly.roam_radius = maxf(bed_size.x, bed_size.y) * 0.55
		add_child(butterfly)

	if animated:
		# Клумба вырастает с пружинкой.
		flowers.scale = Vector3(1.0, 0.01, 1.0)
		var tween := flowers.create_tween()
		tween.tween_property(flowers, "scale", Vector3.ONE, 0.6) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sfx.play("plant")
		Sfx.buzz(25)
		Juice.sparkle(self, global_position + Vector3.UP * 0.5, Color(1.0, 0.8, 0.9), 26)


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
		Models.place(self, "pebble", Vector3(at.x, 0.0, at.y), rng.randf_range(0.1, 0.14), rng.randf() * TAU)


func _flag() -> String:
	return "bed_" + bed_id
