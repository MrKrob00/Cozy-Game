class_name PlotFence
extends Node3D
## Забор участка с калиткой. Стоит в начале координат участка.
## Всё временное, из примитивов (см. Placeholder).

## Отступ забора от края поля в метрах.
@export var fence_offset := 2.5
## Забор с дальней стороны (−Z). Если выключен, там растёт живая изгородь
## в промежутках между постройками.
@export var fence_back := true
## Положение калитки по X на ближней стороне (+Z) и её ширина.
@export var gate_x := 0.0
@export var gate_width := 2.4
@export var random_seed := 7

const WOOD := Color(0.72, 0.52, 0.34)
const WOOD_DARK := Color(0.56, 0.39, 0.25)
const LEAVES := [Color(0.30, 0.62, 0.32), Color(0.40, 0.70, 0.34), Color(0.24, 0.54, 0.36)]
const POST_SPACING := 2.0
const GATE_OPEN_ANGLE := 1.9
const ARROW_HEIGHT := 2.6
const ARROW_COLOR := Color(1.0, 0.80, 0.25)

var _half := Vector2.ZERO
var _gate: Node3D
var _gate_open := true
var _arrow: Node3D
var _arrow_time := 0.0
var _guide_plot: Plot
var _sign_label: Label3D


func _enter_tree() -> void:
	# Размеры нужны участку ещё до нашего _ready.
	var plot := Plot.of(self)
	var field_size := plot.field.size if plot and plot.field else Vector2(24.0, 24.0)
	_half = field_size * 0.5 + Vector2.ONE * fence_offset


func _ready() -> void:
	set_process(false)
	for side: float in [-1.0, 1.0]:
		_fence_run(Vector3(_half.x * side, 0.0, -_half.y), Vector3(_half.x * side, 0.0, _half.y))
	if fence_back:
		_fence_run(Vector3(-_half.x, 0.0, -_half.y), Vector3(_half.x, 0.0, -_half.y))
	else:
		_build_hedge()
	# Ближняя сторона с проёмом калитки.
	var gate_left := gate_x - gate_width * 0.5
	var gate_right := gate_x + gate_width * 0.5
	_fence_run(Vector3(-_half.x, 0.0, _half.y), Vector3(gate_left, 0.0, _half.y))
	_fence_run(Vector3(gate_right, 0.0, _half.y), Vector3(_half.x, 0.0, _half.y))
	for x: float in [gate_left, gate_right]:
		Placeholder.part(self, Placeholder.box(Vector3(0.2, 1.3, 0.2)), WOOD_DARK, Vector3(x, 0.65, _half.y))
		Placeholder.part(self, Placeholder.sphere(0.14), WOOD_DARK, Vector3(x, 1.36, _half.y))
	_build_gate(gate_left)
	_build_signpost.call_deferred(gate_right)


# Столбик с табличкой у калитки, снаружи: имя участка и что его открывает.
func _build_signpost(gate_right: float) -> void:
	var plot := Plot.of(self)
	if plot == null:
		return
	var post := Node3D.new()
	post.name = "Signpost"
	post.position = Vector3(gate_right + 0.9, 0.0, _half.y + 0.8)
	add_child(post)
	Placeholder.part(post, Placeholder.box(Vector3(0.14, 1.6, 0.14)), WOOD_DARK, Vector3(0.0, 0.8, 0.0))
	Placeholder.part(post, Placeholder.box(Vector3(1.5, 0.55, 0.08)), WOOD, Vector3(0.0, 1.45, 0.0))
	Placeholder.part(post, Placeholder.prism(Vector3(0.3, 0.3, 0.08)), WOOD, Vector3(0.9, 1.45, 0.0),
			Vector3(0.0, 0.0, -90.0))
	Placeholder.bake_tree(post)
	_sign_label = Label3D.new()
	_sign_label.position = Vector3(0.0, 2.15, 0.0)
	_sign_label.font_size = 54
	_sign_label.pixel_size = 0.006
	_sign_label.outline_size = 18
	_sign_label.modulate = Color(1.0, 0.97, 0.88)
	_sign_label.outline_modulate = Color(0.33, 0.22, 0.12)
	_sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign_label.no_depth_test = true
	post.add_child(_sign_label)
	_update_sign(plot)
	plot.unlocked.connect(_update_sign.bind(plot))
	plot.completed.connect(_update_sign.bind(plot))


func _update_sign(plot: Plot) -> void:
	if _sign_label == null:
		return
	var text := L.t(plot.plot_name)
	if not plot.is_unlocked():
		text += "\n" + L.t("закрыто")
		_sign_label.modulate = Color(0.85, 0.82, 0.78)
	elif plot.is_completed():
		text += "\n" + L.t("выкошен")
		_sign_label.modulate = Color(0.8, 1.0, 0.7)
	else:
		_sign_label.modulate = Color(1.0, 0.92, 0.55)
	_sign_label.text = text


## Стрелка над калиткой: зовёт на только что открытый участок и исчезает,
## когда игрок туда зашёл.
func show_guide_arrow(plot: Plot) -> void:
	if _arrow:
		return
	_guide_plot = plot
	_arrow = Node3D.new()
	_arrow.name = "GuideArrow"
	add_child(_arrow)
	_arrow.global_position = get_gate_position() + Vector3.UP * ARROW_HEIGHT
	for arrow_part in [
		Placeholder.part(_arrow, Placeholder.cylinder(0.0, 0.7, 0.45), ARROW_COLOR, Vector3.ZERO),
		Placeholder.part(_arrow, Placeholder.cylinder(0.17, 0.6), ARROW_COLOR, Vector3(0.0, 0.62, 0.0)),
	]:
		arrow_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Placeholder.bake_tree(_arrow)
	_arrow.scale = Vector3.ONE * 0.01
	var grow := _arrow.create_tween()
	grow.tween_property(_arrow, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	set_process(true)


func _process(delta: float) -> void:
	if _arrow == null:
		set_process(false)
		return
	_arrow_time += delta
	_arrow.position.y = _arrow_base_y() + sin(_arrow_time * 3.5) * 0.25
	_arrow.rotate_y(delta * 1.8)
	var village := get_tree().get_first_node_in_group("village") as Village
	if village and village.current_plot == _guide_plot and _guide_plot.get_progress() > 0.0:
		var arrow := _arrow
		_arrow = null
		var shrink := arrow.create_tween()
		shrink.tween_property(arrow, "scale", Vector3.ONE * 0.01, 0.3).set_ease(Tween.EASE_IN)
		shrink.tween_callback(arrow.queue_free)


func has_guide_arrow() -> bool:
	return _arrow != null


func _arrow_base_y() -> float:
	return to_local(get_gate_position()).y + ARROW_HEIGHT


## Углы забора в мировых координатах, по кругу.
func get_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for local: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(to_global(Vector3(local.x * _half.x, 0.0, local.y * _half.y)))
	return corners


## Середина калитки в мировых координатах.
func get_gate_position() -> Vector3:
	return to_global(Vector3(gate_x, 0.0, _half.y))


## Проход через калитку (мировые X, Z): от края участка до улицы за забором.
func get_gate_rect(walk_margin: float) -> Rect2:
	var gate := get_gate_position()
	# Наружу калитка смотрит вдоль локальной оси +Z (участок может быть повёрнут).
	var outward := global_basis.z.normalized()
	var across := global_basis.x.normalized() * (gate_width - 0.7) * 0.5
	var inside := gate - outward * (fence_offset - walk_margin + 0.4)
	var outside := gate + outward * 1.4
	var rect := Rect2(Vector2(inside.x - across.x, inside.z - across.z), Vector2.ZERO)
	for corner: Vector3 in [inside + across, outside - across, outside + across]:
		rect = rect.expand(Vector2(corner.x, corner.z))
	return rect


## Открывает или закрывает калитку.
func set_gate_open(open: bool, animated: bool) -> void:
	_gate_open = open
	if _gate == null:
		return
	var angle := GATE_OPEN_ANGLE if open else 0.0
	if not animated:
		_gate.rotation.y = angle
		return
	Sfx.play("pop")
	Juice.sparkle(self, _gate.global_position + Vector3(gate_width * 0.5, 0.8, 0.0))
	var tween := create_tween()
	tween.tween_property(_gate, "rotation:y", angle, 0.9) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Створка на петлях у левого столба; открывается внутрь участка.
func _build_gate(gate_left: float) -> void:
	_gate = Node3D.new()
	_gate.add_to_group("shadow_dynamic")
	_gate.position = Vector3(gate_left + 0.1, 0.0, _half.y)
	add_child(_gate)
	var width := gate_width - 0.25
	for height: float in [0.3, 0.8]:
		Placeholder.part(_gate, Placeholder.box(Vector3(width, 0.1, 0.06)), WOOD,
				Vector3(width * 0.5, height, 0.0))
	var planks := 5
	for i in planks:
		var x := width * (i + 0.5) / planks
		Placeholder.part(_gate, Placeholder.box(Vector3(0.16, 0.9 + 0.08 * sin(PI * (i + 0.5) / planks), 0.05)),
				WOOD, Vector3(x, 0.5, 0.03))
	_gate.rotation.y = GATE_OPEN_ANGLE if _gate_open else 0.0


func _fence_run(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var yaw := atan2(to.x - from.x, to.z - from.z)
	var posts := maxi(roundi(length / POST_SPACING), 1)
	var post := Placeholder.box(Vector3(0.14, 0.9, 0.14))
	for i in posts + 1:
		Placeholder.part(self, post, WOOD, from.lerp(to, float(i) / posts) + Vector3(0.0, 0.45, 0.0))
	for height: float in [0.35, 0.7]:
		var rail := Placeholder.part(self, Placeholder.box(Vector3(0.06, 0.08, length)), WOOD,
				(from + to) * 0.5 + Vector3(0.0, height, 0.0))
		rail.rotation.y = yaw


# Кусты вдоль дальней стороны, в промежутках между постройками.
func _build_hedge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed + 1
	var plot := Plot.of(self)
	var buildings: Array[PlotProp] = []
	if plot:
		for node in plot.members("plot_light"):
			var prop := node as PlotProp
			if prop and prop.kind in [PlotProp.Kind.HOUSE, PlotProp.Kind.SHED]:
				buildings.append(prop)
	var z := -_half.y - 0.3
	var x := -_half.x
	while x <= _half.x:
		var blocked := false
		for building in buildings:
			if absf(to_local(building.global_position).x - x) < building.get_width() * 0.5 + 0.7:
				blocked = true
		if not blocked:
			var size := rng.randf_range(0.6, 0.85)
			var color: Color = LEAVES[rng.randi() % LEAVES.size()]
			var bush := Placeholder.part(self, Placeholder.sphere(size), color,
					Vector3(x, size * 0.6, z + rng.randf_range(-0.2, 0.2)))
			bush.scale = Vector3(1.0, 0.8, 1.0)
		x += 1.0
