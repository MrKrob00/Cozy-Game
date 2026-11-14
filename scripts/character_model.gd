class_name CharacterModel
extends Node3D
## Готовая модель с анимациями: люди Kenney Mini Characters, зверьки Kenney
## Cube Pets, лягушка Quaternius (все CC0, см. CREDITS.md).
##
## Ставит модели материал игры (свет дня считают наши шейдеры), подгоняет
## рост, включает тень и даёт простое управление анимацией.

const SHADER := preload("res://shaders/toon_skin.gdshader")
## Анимации, которые идут по кругу.
const LOOPED := ["idle", "walk", "sprint", "run", "sit", "eat", "dance", "holding-both", "push-walk", "push-idle",
		"FrogArmature|Frog_Idle"]

## Материалы по паре «текстура, цвет»: общие на все модели.
static var _materials: Dictionary = {}

var animation: AnimationPlayer
var skeleton: Skeleton3D
## Корень загруженной сцены (он отмасштабирован под нужный рост).
var body: Node3D


## Загружает модель (.glb из assets) и подгоняет её высоту, метры.
## Мелочи (птицы на газоне) могут не отбрасывать тень: так дешевле.
static func create(path: String, height: float, casts_shadow := true) -> CharacterModel:
	var model := CharacterModel.new()
	model.body = (load(path) as PackedScene).instantiate()
	model.add_child(model.body)
	model._setup(height, casts_shadow)
	return model


## Включает анимацию; speed — во сколько раз быстрее обычного.
func play(animation_name: String, speed := 1.0, blend := 0.2) -> void:
	if animation == null or not animation.has_animation(animation_name):
		return
	animation.speed_scale = speed
	if animation.current_animation != animation_name:
		animation.play(animation_name, blend)


## Новая анимация: base, в которой кости bones берутся из позы overlay.
## Так «идти» и «держать двумя руками» складываются в «катить косилку».
func combine(new_name: String, base: String, overlay: String, bones: Array[String]) -> void:
	if animation == null or not animation.has_animation(base) or not animation.has_animation(overlay):
		return
	var result: Animation = animation.get_animation(base).duplicate()
	var source := animation.get_animation(overlay)
	for track in range(result.get_track_count() - 1, -1, -1):
		if _track_bone(result, track) in bones:
			result.remove_track(track)
	for track in source.get_track_count():
		if not _track_bone(source, track) in bones:
			continue
		var added := result.add_track(source.track_get_type(track))
		result.track_set_path(added, source.track_get_path(track))
		# Поза, а не движение: хватает первого ключа.
		result.track_insert_key(added, 0.0, source.track_get_key_value(track, 0))
	result.loop_mode = Animation.LOOP_LINEAR
	animation.get_animation_library("").add_animation(new_name, result)


## Узел, привязанный к кости: на него вешают шляпу и другие предметы.
## Размеры на нём — в метрах мира, масштаб модели уже учтён.
func attach(bone: String) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE / body.scale.x
	attachment.add_child(holder)
	return holder


## Коробка детали по имени её узла (например «head-mesh») в координатах
## этого узла, метры; в позе покоя.
func part_box(part_name: String) -> AABB:
	for node in body.find_children(part_name, "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var box: AABB = _to_body(instance) * instance.mesh.get_aabb()
		return AABB(box.position * body.scale.x + body.position, box.size * body.scale.x)
	return AABB()


## Высота кости над землёй в позе покоя, метры.
func bone_height(bone: String) -> float:
	var index := skeleton.find_bone(bone) if skeleton else -1
	if index == -1:
		return 0.0
	var at: Vector3 = _to_body(skeleton) * skeleton.get_bone_global_rest(index).origin
	return at.y * body.scale.x + body.position.y


func _setup(height: float, casts_shadow: bool) -> void:
	var players := body.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation = players[0]
		for animation_name in animation.get_animation_list():
			if animation_name in LOOPED:
				animation.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		skeleton = skeletons[0]

	# Рост: по коробке всех деталей в позе покоя.
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	var box := AABB()
	var first := true
	for node in meshes:
		var instance := node as MeshInstance3D
		var part: AABB = _to_body(instance) * instance.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	if box.size.y > 0.0:
		var factor := height / box.size.y
		body.scale = Vector3.ONE * factor
		body.position.y = -box.position.y * factor

	for node in meshes:
		var instance := node as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			instance.set_surface_override_material(surface, _material_for(instance.mesh.surface_get_material(surface)))
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Тень — двойник со скелетом, землёй считается низ модели (Shadows).
		if casts_shadow:
			instance.set_meta("shadow_flat", true)
			instance.add_to_group("shadow_caster")
	if casts_shadow:
		Graphics.casters_changed.emit.call_deferred()


# Положение детали относительно корня модели (узлы ещё могут быть не в дереве).
func _to_body(node: Node3D) -> Transform3D:
	var transform_to := Transform3D.IDENTITY
	var current: Node = node
	while current != body and current is Node3D:
		transform_to = (current as Node3D).transform * transform_to
		current = current.get_parent()
	return transform_to


static func _material_for(source: Material) -> ShaderMaterial:
	var texture: Texture2D = null
	var color := Color.WHITE
	var base := source as BaseMaterial3D
	if base:
		texture = base.albedo_texture
		color = base.albedo_color
	var key := [texture, color]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("albedo", color)
		if texture:
			material.set_shader_parameter("albedo_tex", texture)
		_materials[key] = Graphics.track(material)
	return _materials[key]


# Имя кости, которой управляет дорожка анимации (пусто — не кость).
static func _track_bone(source: Animation, track: int) -> String:
	var path := source.track_get_path(track)
	return path.get_subname(0) if path.get_subname_count() > 0 else ""
