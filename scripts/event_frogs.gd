class_name EventFrogs
extends Node3D
## Фруктовый сад: лягушки выпрыгивают из пруда на берег и квакают по
## очереди; скосишь траву у лягушки — она перепрыгивает на лист кувшинки и
## квакает оттуда. Подъедешь к лягушке вплотную — она пугается и ныряет
## в пруд; спугнёшь всех — хор кончается. Иначе через минуту все ныряют сами.
## Просто красота.
## Лягушка — Quaternius (CC0), кваканье — записи с OpenGameArt (CREDITS.md).

const COUNT := 4
## Ближе этого к косилке лягушка пугается и ныряет, метры.
const SCARE := 1.6
const HEIGHT := 0.4
const LIFE := 60.0
const HOP := 0.5
## Кваканье — раз в столько секунд, по очереди.
const CROAK_EVERY := 0.85
const BANK := 0.08

var _pond: PlotProp
var _field: MowField
var _player: Node3D
var _frogs: Array[Dictionary] = []
var _lilies: Array[Vector3] = []
var _time := 0.0
var _croak := 1.5
var _turn := 0
var _leaving := false


static func start(host: Node, orchard: Node) -> bool:
	if orchard == null:
		return false
	var pond := orchard.get_node_or_null("Pond") as PlotProp
	if pond == null:
		return false
	var frogs := EventFrogs.new()
	frogs.name = "FrogChorus"
	frogs._pond = pond
	frogs._field = (orchard as Plot).field
	host.add_child(frogs)
	return true


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_lilies = _pond.get_lily_spots()
	for i in COUNT:
		var angle := TAU * i / COUNT + randf_range(-0.3, 0.3)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var holder := Node3D.new()
		add_child(holder)
		var model := CharacterModel.create("res://assets/animals/frog.glb", HEIGHT, false)
		model.rotation.y = PI
		holder.add_child(model)
		model.play("FrogArmature|Frog_Idle", 1.0, 0.0)
		var water := _pond.global_position + out * (PlotProp.POND_RADIUS - 0.6) + Vector3.UP * 0.02
		# На камнях у самой воды: в траве лягушку не видно.
		var bank := _pond.global_position + out * (PlotProp.POND_RADIUS + BANK)
		holder.global_position = water
		holder.scale = Vector3.ONE * 0.01
		var frog := {"node": holder, "model": model, "at": bank, "on_lily": false, "busy": true, "gone": false}
		_frogs.append(frog)
		# Выныривают по очереди и прыгают на берег.
		get_tree().create_timer(0.3 + i * 0.35).timeout.connect(func() -> void:
			if is_instance_valid(holder):
				holder.scale = Vector3.ONE
				_hop(frog, bank))


func _process(delta: float) -> void:
	_time += delta
	if _time > LIFE and not _leaving:
		_leaving = true
		for frog in _frogs:
			if not frog["gone"]:
				frog["gone"] = true
				_hop(frog, _pond.global_position + (frog["at"] - _pond.global_position).normalized() * 1.2, true)
		get_tree().create_timer(HOP + 0.6).timeout.connect(queue_free)
	if _leaving:
		return
	# Косилка вплотную — лягушка пугается и ныряет; спугнули всех — хор кончился.
	for frog in _frogs:
		if frog["busy"] or frog["gone"] or _player == null:
			continue
		var at: Vector3 = (frog["node"] as Node3D).global_position
		if Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z).length() < SCARE:
			_scare(frog)
	if _frogs.all(func(f: Dictionary) -> bool: return f["gone"]):
		_leaving = true
		get_tree().create_timer(HOP + 0.6).timeout.connect(queue_free)
		return
	for frog in _frogs:
		if frog["busy"] or frog["on_lily"] or frog["gone"] or _lilies.is_empty():
			continue
		# Траву у лягушки скосили — она перебирается на кувшинку. Сразу у воды
		# травы нет вовсе (берег), поэтому смотрим чуть дальше от пруда.
		var out: Vector3 = (frog["at"] - _pond.global_position).normalized()
		if _field and _field.is_open_lawn(frog["at"] + out * 0.7):
			frog["on_lily"] = true
			var lily: Vector3 = _lilies[_frogs.find(frog) % _lilies.size()]
			_hop(frog, lily + Vector3.UP * 0.04)
	_croak -= delta
	if _croak <= 0.0:
		_croak = CROAK_EVERY * randf_range(0.8, 1.3)
		_turn = (_turn + 1 + randi() % 2) % _frogs.size()
		_croak_frog(_frogs[_turn])


func _croak_frog(frog: Dictionary) -> void:
	if frog["busy"] or frog["gone"]:
		return
	var node: Node3D = frog["node"]
	var distance := _player.global_position.distance_to(node.global_position) if _player else 8.0
	if distance < 16.0:
		Sfx.play("frog", -8.0 - distance * 0.9, randf_range(0.9, 1.15), 0.0)
	# Горло раздувается: лягушка на миг шире и ниже.
	var model: Node3D = frog["model"]
	var tween := model.create_tween()
	tween.tween_property(model, "scale", Vector3(1.25, 0.85, 1.25), 0.12)
	tween.tween_property(model, "scale", Vector3.ONE, 0.25)


# Испуг: квак-вскрик и нырок в пруд.
func _scare(frog: Dictionary) -> void:
	frog["gone"] = true
	Sfx.play("frog", -6.0, 1.35, 0.0)
	var node: Node3D = frog["node"]
	var into := _pond.global_position + (node.global_position - _pond.global_position).normalized() \
			* (PlotProp.POND_RADIUS - 1.0)
	_hop(frog, into, true)


## Сколько лягушек ещё сидит (не спугнуты).
func frogs_left() -> int:
	return _frogs.filter(func(f: Dictionary) -> bool: return not f["gone"]).size()


# Прыжок дугой к точке; dive — нырок в пруд (исчезает).
func _hop(frog: Dictionary, to: Vector3, dive := false) -> void:
	var node: Node3D = frog["node"]
	var model: CharacterModel = frog["model"]
	frog["busy"] = true
	var from := node.global_position
	var heading := to - from
	if Vector2(heading.x, heading.z).length() > 0.01:
		node.rotation.y = atan2(-heading.x, -heading.z)
	if model.animation and model.animation.has_animation("FrogArmature|Frog_Jump"):
		model.animation.play("FrogArmature|Frog_Jump", 0.05)
		model.animation.seek(0.0, true)
	Sfx.play("hop", -12.0, 1.1, 0.1)
	var tween := node.create_tween()
	tween.tween_method(func(t: float) -> void:
		node.global_position = from.lerp(to, t) + Vector3.UP * 0.5 * 4.0 * t * (1.0 - t), 0.0, 1.0, HOP)
	tween.tween_callback(func() -> void:
		frog["busy"] = false
		frog["at"] = to
		if dive:
			Juice.puff(get_parent(), to + Vector3.UP * 0.05, 4)
			node.visible = false
		else:
			model.play("FrogArmature|Frog_Idle", 1.0, 0.1))
