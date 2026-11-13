class_name Shadows
extends Node3D
## Тени предметов без карты теней (подход из Voxel-RTS, cast_shadows.gd).
##
## Каждая склеенная модель, отбрасывающая тень, получает «тень-двойника»:
## ту же модель с шейдером shadow_cast, который сплющивает её вдоль солнечного
## луча на землю. Двойников видят только свои камеры — ортографические, сверху.
## Получается чёрно-белая картинка теней в окне вокруг игрока; земля и трава
## читают из неё одну точку.
##
## Картинок две, чтобы движение игрока не перерисовывало все деревья:
##   неподвижная — дома, деревья, заборы; рисуется, только когда сдвинулось
##                 окно (раз на несколько метров пути) или что-то изменилось;
##   итоговая    — неподвижная картинка одним прямоугольником плюс то, что
##                 движется (игрок, зверьки, калитки); рисуется, когда что-то
##                 из этого сдвинулось, не чаще 30 раз в секунду.

## Слои рендера двойников: основная камера их не видит.
const LAYER_STATIC := 1 << 19
const LAYER_DYNAMIC := 1 << 18
const LAYER := LAYER_STATIC | LAYER_DYNAMIC
## Сторона окна в метрах. Камера на дальнем масштабе видит меньше.
const WINDOW := 56.0
## Окно сдвигается шагами, чтобы неподвижные тени перерисовывались редко.
const WINDOW_STEP := 6.0
## Доля окна у края, где тени плавно гаснут.
const EDGE_FADE := 0.06
const MIN_INTERVAL := 1.0 / 30.0
## Раз в столько секунд обе картинки перерисовываются в любом случае
## (что-то показалось или спряталось, а движения не было).
const REFRESH := 2.0
const CAST_SHADER := preload("res://shaders/shadow_cast.gdshader")

var _static_view: SubViewport
var _final_view: SubViewport
var _static_camera: Camera3D
var _final_camera: Camera3D
var _backdrop: MeshInstance3D
var _cast_material: ShaderMaterial
var _target: Node3D
var _center := Vector2(INF, INF)
## Двойники движущихся моделей и их последнее состояние.
var _dynamic: Array[MeshInstance3D] = []
var _last: Dictionary = {}
var _static_dirty := true
var _final_dirty := true
## Сдвиг окна идёт в два кадра, иначе земля один кадр читала бы старую
## картинку по новому окну (все тени мигали не на своём месте):
##   STATIC_PENDING — окно сдвинулось, неподвижная картинка ждёт перерисовки;
##   STATIC_DRAWN   — она нарисована, в этом кадре переезжает всё остальное.
enum Shift { NONE, STATIC_PENDING, STATIC_DRAWN }
var _shift := Shift.NONE
## Неподвижная картинка перерисована в прошлом кадре.
var _static_drawn := false
var _since_render := 0.0
var _since_refresh := 0.0
## Сколько раз перерисовывалась каждая картинка (для проверок).
var static_renders := 0
var final_renders := 0


func _ready() -> void:
	_cast_material = ShaderMaterial.new()
	_cast_material.shader = CAST_SHADER
	_cast_material.set_shader_parameter("day_dir", Graphics.sun_direction)

	_static_view = _make_view("StaticShade")
	_static_camera = _make_camera(_static_view, LAYER_STATIC)
	_final_view = _make_view("FinalShade")
	_final_camera = _make_camera(_final_view, LAYER_DYNAMIC)

	# Неподвижные тени попадают в итоговую картинку одним прямоугольником.
	var plane := PlaneMesh.new()
	plane.size = Vector2(WINDOW, WINDOW)
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop_material.albedo_texture = _static_view.get_texture()
	backdrop_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	backdrop_material.no_depth_test = true
	backdrop_material.render_priority = -10
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "StaticBackdrop"
	_backdrop.mesh = plane
	_backdrop.material_override = backdrop_material
	_backdrop.layers = LAYER_DYNAMIC
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backdrop)

	_target = get_tree().get_first_node_in_group("player") as Node3D
	Graphics.casters_changed.connect(_add_casters)
	Graphics.quality_changed.connect(_apply_quality)
	_apply_quality()
	_add_casters()


func _process(delta: float) -> void:
	_since_render += delta
	_since_refresh += delta
	match _shift:
		Shift.NONE:
			_follow_target()
		Shift.STATIC_DRAWN:
			# Неподвижная картинка уже нарисована для нового окна: теперь
			# переезжают итоговая камера и параметры материалов — все разом.
			_shift = Shift.NONE
			_final_camera.global_position = _static_camera.global_position
			_backdrop.global_position = Vector3(_center.x, -1.0, _center.y)
			var corner := _center - Vector2.ONE * WINDOW * 0.5
			Graphics.set_shade(_final_view.get_texture(),
					Vector4(corner.x, corner.y, 1.0 / WINDOW, EDGE_FADE))
			_render_final()
			return
	if _shift == Shift.STATIC_PENDING:
		# Окно сдвинулось: в этом кадре рисуется только неподвижная картинка.
		# Итоговую не трогаем — её подложка и камера ещё на старом месте,
		# и земля читает её по старому окну.
		_shift = Shift.STATIC_DRAWN
		_static_dirty = false
		_since_refresh = 0.0
		static_renders += 1
		_static_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if _static_drawn:
		# Неподвижная картинка обновилась в прошлом кадре — итоговая за ней.
		_static_drawn = false
		_final_dirty = true
	if not _final_dirty:
		for proxy in _dynamic:
			if not is_instance_valid(proxy):
				continue
			var state := [proxy.global_transform, proxy.is_visible_in_tree()]
			if _last.get(proxy) != state:
				_last[proxy] = state
				_final_dirty = true
	if _since_refresh >= REFRESH:
		_since_refresh = 0.0
		_static_dirty = true
	if _static_dirty:
		_static_dirty = false
		_static_drawn = true
		static_renders += 1
		_static_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if _final_dirty and _since_render >= MIN_INTERVAL:
		_render_final()


func _render_final() -> void:
	_final_dirty = false
	_since_render = 0.0
	final_renders += 1
	_final_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## Сколько моделей отбрасывают тень (для проверок).
func caster_count() -> int:
	return get_tree().get_nodes_in_group("shadow_caster").size()


## Сколько из них движутся.
func dynamic_count() -> int:
	return _dynamic.size()


## Итоговая картинка теней (для проверок).
func get_texture() -> Texture2D:
	return _final_view.get_texture()


func _make_view(view_name: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.transparent_bg = false
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.positional_shadow_atlas_size = 0
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	return view


func _make_camera(view: SubViewport, mask: int) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = WINDOW
	camera.near = 1.0
	camera.far = 100.0
	camera.cull_mask = mask
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	camera.environment = environment
	view.add_child(camera)
	camera.current = true
	return camera


func _apply_quality() -> void:
	var side: int = Graphics.preset["shade_size"]
	_static_view.size = Vector2i(side, side)
	_final_view.size = Vector2i(side, side)
	_static_dirty = true


# Окно идёт за игроком шагами по сетке. Здесь сдвигается только камера
# неподвижной картинки; остальное — кадром позже (см. Shift).
func _follow_target() -> void:
	if _target == null:
		return
	var at := Vector2(_target.global_position.x, _target.global_position.z)
	var snapped := (at / WINDOW_STEP).round() * WINDOW_STEP
	if snapped == _center:
		return
	_center = snapped
	_static_camera.global_position = Vector3(_center.x, 50.0, _center.y)
	_shift = Shift.STATIC_PENDING


# Новым моделям из группы «shadow_caster» — по двойнику на нужном слое.
func _add_casters() -> void:
	for node in get_tree().get_nodes_in_group("shadow_caster"):
		var caster := node as MeshInstance3D
		if caster == null or caster.has_meta("shadow_proxy"):
			continue
		var dynamic := _is_dynamic(caster)
		var proxy := MeshInstance3D.new()
		proxy.name = "ShadowProxy"
		proxy.mesh = caster.mesh
		proxy.material_override = _cast_material
		proxy.layers = LAYER_DYNAMIC if dynamic else LAYER_STATIC
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		caster.add_child(proxy)
		caster.set_meta("shadow_proxy", proxy)
		if dynamic:
			_dynamic.append(proxy)
	# Двойники удалённых моделей (перестроенная косилка) выбрасываем из списка.
	var alive: Array[MeshInstance3D] = []
	for proxy: Variant in _dynamic:
		if is_instance_valid(proxy):
			alive.append(proxy)
	_dynamic = alive
	_static_dirty = true


# Движется ли модель: она внутри узла из группы «shadow_dynamic».
func _is_dynamic(node: Node) -> bool:
	var current := node
	while current:
		if current.is_in_group("shadow_dynamic"):
			return true
		current = current.get_parent()
	return false
