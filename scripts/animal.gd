class_name Animal
extends Interactable
## Зверёк в траве. Косилка в него упирается и навредить не может.
## Игрок переносит зверька — тот уходит в свой уголок: ёжик семенит,
## перебирая лапками, кот бежит (анимация модели), лягушка прыгает.

enum Kind { HEDGEHOG, CAT, FROG }

@export var kind := Kind.HEDGEHOG
@export var animal_id := "hedgehog"
@export var display_name := "ёжика"
## Маркер уголка, куда зверёк уходит.
@export var home_path: NodePath
## С какого расстояния игрок «замечает» зверька.
@export var notice_distance := 2.6

var _moved := false
var _noticed := false
var _busy := false
var _body: StaticBody3D
var _model: Node3D
var _time := 0.0
var _last_hop := -1
## Модель со скелетом и анимациями (кот, лягушка).
var _figure: CharacterModel
## Ёжик: тельце и лапки (лапки перебирают на бегу) и где лапки стоят.
var _hog_body: Node3D
var _feet: Array[MeshInstance3D] = []
var _feet_rest: Array[Vector3] = []

## Скорость бега в свой уголок, м/с (у кого бег, а не прыжки).
const RUN_SPEED := {Kind.HEDGEHOG: 1.7, Kind.CAT: 3.2}
## Ёжик: длина шажка, м, и насколько лапка выносится вперёд и поднимается.
const HOG_STRIDE := 0.13
const HOG_STEP := 0.07
const HOG_LIFT := 0.045
## Лягушка: время одного прыжка, с.
const FROG_HOP := 0.45
## Лапки ёжика (как HEDGEHOG_FEET в tools/make_models.py), при масштабе модели.
const HOG_SCALE := 0.9
const HOG_FEET: Array[Vector3] = [Vector3(-0.14, 0.04, -0.2), Vector3(0.14, 0.04, -0.2),
		Vector3(-0.16, 0.04, 0.24), Vector3(0.16, 0.04, 0.24)]


func _enter_tree() -> void:
	super()
	add_to_group("animal")
	add_to_group("shadow_dynamic")


func _ready() -> void:
	# Зверёк сам уходит в свой уголок, когда косилка подъезжает вплотную.
	auto_interact = true
	_build_visuals()
	if GameState.has_flag(_flag()):
		_moved = true
		_settle_at_home()


func _process(delta: float) -> void:
	# Лёгкое «дыхание».
	_time += delta
	if not _busy:
		_model.scale = Vector3.ONE * (1.0 + sin(_time * 2.5) * 0.03)
	if _moved or _noticed:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_to(global_position) < notice_distance:
		_noticed = true
		Sfx.play("squeak")
		Juice.floating_text(self, global_position + Vector3.UP * 0.9, "!", Color(1.0, 0.9, 0.4))
		GameState.toast("Тут кто-то есть! Косилка его не заденет — подъезжайте ближе, и он уйдёт")
		_hop_in_place()


func is_moved() -> bool:
	return _moved


func get_prompt() -> String:
	return L.t("Перенести %s") % L.t(display_name)


func can_interact(_player: Player) -> bool:
	return not _moved and not _busy


func interact(_player: Player) -> void:
	_moved = true
	_busy = true
	GameState.set_flag(_flag())
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	Sfx.play("squeak", 0.0, 1.15)
	Sfx.buzz(20)

	var home := get_node_or_null(home_path) as Node3D
	var from := global_position
	var to := home.global_position if home else from + Vector3(3.0, 0.0, 0.0)
	var distance := from.distance_to(to)
	var hops := maxi(roundi(distance / 1.4), 1)
	look_at(Vector3(to.x, from.y, to.z), Vector3.UP)
	var duration: float = distance / RUN_SPEED[kind] if RUN_SPEED.has(kind) else FROG_HOP * hops
	if kind == Kind.CAT and _figure:
		_figure.play("run", 1.0, 0.1)

	var tween := create_tween()
	tween.tween_method(_travel.bind(from, to, hops), 0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		_arrive()
		Juice.sparkle(self, global_position + Vector3.UP * 0.4, Color(1.0, 0.75, 0.8))
		GameState.save_game())


## Шаг пути в свой уголок: progress 0–1 от from к to. Ёжик и кот бегут,
## лягушка делает hops прыжков. (Его же зовёт трейлер, tools/trailer.gd.)
func _travel(progress: float, from: Vector3, to: Vector3, hops: int) -> void:
	global_position = from.lerp(to, progress)
	match kind:
		Kind.HEDGEHOG:
			_scurry(from.distance_to(to) * progress)
		Kind.CAT:
			pass
		_:
			var bounce := absf(sin(progress * PI * hops))
			_model.position.y = bounce * 0.5
			# Приземляясь, лягушка сплющивается, в прыжке вытягивается.
			_model.scale = Vector3.ONE.lerp(Vector3(1.2, 0.75, 1.2), 1.0 - minf(bounce * 4.0, 1.0))
			var hop := mini(int(progress * hops), hops - 1)
			if hop != _last_hop:
				_last_hop = hop
				Sfx.play("hop", -6.0, 1.0, 0.12)
				if _figure and _figure.animation:
					_figure.animation.play("FrogArmature|Frog_Jump", 0.05)
					_figure.animation.seek(0.0, true)
					_figure.animation.speed_scale = 0.88 / FROG_HOP


# Ёжик семенит: лапки перебирают по диагонали (левая передняя с правой
# задней), тельце мелко подпрыгивает и наклоняется вперёд. travelled — сколько
# пробежал, м: шаги идут в такт пути.
func _scurry(travelled: float) -> void:
	if _hog_body == null:
		return
	var phase := travelled / HOG_STRIDE * PI
	for i in _feet.size():
		var pair := 1.0 if i == 0 or i == 3 else -1.0
		var swing := sin(phase) * pair
		var lift := maxf(cos(phase) * pair, 0.0)
		_feet[i].position = _feet_rest[i] + Vector3(0.0, lift * HOG_LIFT, -swing * HOG_STEP)
	_hog_body.position.y = absf(sin(phase)) * 0.035
	_hog_body.rotation.x = -0.12
	_hog_body.rotation.z = sin(phase) * 0.05


# Добежал: лапки и тельце — на место, анимация — обычная.
func _arrive() -> void:
	_busy = false
	_model.position.y = 0.0
	_model.scale = Vector3.ONE
	if _hog_body:
		_hog_body.position = Vector3.ZERO
		_hog_body.rotation = Vector3.ZERO
		for i in _feet.size():
			_feet[i].position = _feet_rest[i]
	if _figure:
		_figure.play("idle" if kind == Kind.CAT else "FrogArmature|Frog_Idle", 1.0, 0.2)


func _hop_in_place() -> void:
	_busy = true
	var tween := create_tween()
	Sfx.play("hop", -6.0)
	tween.tween_property(_model, "position:y", 0.45, 0.14).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", 0.0, 0.16).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _busy = false)


func _settle_at_home() -> void:
	var home := get_node_or_null(home_path) as Node3D
	if home:
		global_position = home.global_position
	_body.process_mode = Node.PROCESS_MODE_DISABLED


func _flag() -> String:
	return "animal_" + animal_id


func _build_visuals() -> void:
	_model = Node3D.new()
	add_child(_model)
	match kind:
		Kind.CAT:
			_build_cat()
		Kind.FROG:
			_build_frog()
		_:
			_build_hedgehog()

	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.38
	cylinder.height = 0.7
	shape.shape = cylinder
	shape.position = Vector3(0.0, 0.35, 0.0)
	_body.add_child(shape)
	add_child(_body)


# Лягушка — модель Quaternius (CC0), сидит и дышит.
func _build_frog() -> void:
	var frog := CharacterModel.create("res://assets/animals/frog.glb", 0.24)
	frog.rotation.y = PI
	_model.add_child(frog)
	frog.play("FrogArmature|Frog_Idle", 1.0, 0.0)
	_figure = frog


# Кот — модель Kenney Cube Pets (CC0).
func _build_cat() -> void:
	var cat := CharacterModel.create("res://assets/animals/cat.glb", 0.62)
	cat.rotation.y = PI
	_model.add_child(cat)
	cat.play("idle", 1.0, 0.0)
	_figure = cat
	# На празднике кот танцует.
	var village := get_tree().get_first_node_in_group("village") as Village
	if village:
		village.festival_started.connect(func(_announce: bool) -> void: cat.play("dance"))


# Ёжик — своя модель (tools/make_models.py): готовой в нужном стиле не нашлось.
# Тельце и лапки отдельно: на бегу лапки перебирают (_scurry).
func _build_hedgehog() -> void:
	_hog_body = Node3D.new()
	_hog_body.name = "Body"
	_model.add_child(_hog_body)
	Models.place(_hog_body, "hedgehog", Vector3.ZERO, HOG_SCALE)
	for at in HOG_FEET:
		var foot := Models.place(_model, "hedgehog_foot", at * HOG_SCALE, HOG_SCALE, 0.0, false)
		foot.set_meta("no_bake", true)
		_feet.append(foot)
		_feet_rest.append(foot.position)
