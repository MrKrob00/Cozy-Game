extends SceneTree
## Запекает окружение деревни в scenes/baked/ (см. scripts/map_bake.gd).
##
## Запуск из папки проекта:
##   godot --headless --path . --script tools/bake_map.gd
##
## Игровые классы здесь не используются как типы: скрипт компилируется
## раньше, чем регистрируются автозагрузки.

var _placeholder: GDScript
var _map_bake: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.set_meta("baking_map", true)
	_placeholder = load("res://scripts/placeholder.gd")
	_map_bake = load("res://scripts/map_bake.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_map_bake.DIRECTORY))
	var game_state := root.get_node("GameState")
	# Наборы графики отличаются только густотой россыпей.
	for quality: int in [2, 1, 0]:
		game_state.clear()
		game_state.title_seen = true
		game_state.graphics_quality = quality
		change_scene_to_file("res://scenes/village.tscn")
		for i in 8:
			await process_frame
		var decor: Node3D = current_scene.get_node("Decor")
		var scatter: Node3D = decor.get_node("Scatter")
		if quality == 2:
			var base := _export(decor, [scatter])
			base.name = "Decor"
			base.transform = Transform3D.IDENTITY
			base.set_meta("lamp_runs", decor.get("_lamp_runs"))
			base.set_meta("bake_key", _map_bake.source_key())
			_save(base, _map_bake.BASE)
		var copy := _export(scatter, [])
		_save(copy, _map_bake.SCATTER % quality)
	quit()


# Копия узла без скриптов и материалов: модели, коллизии и пустые узлы.
func _export(source: Node, skip: Array) -> Node3D:
	if source in skip or source.name == &"ShadowProxy" or not source is Node3D:
		return null
	var copy: Node3D
	if source is MeshInstance3D:
		var instance := source as MeshInstance3D
		if instance.mesh == null or not instance.visible:
			return null
		var mesh_copy := MeshInstance3D.new()
		# Модель из импортированного файла копируем: чужой ресурс в сцену не сохранить.
		mesh_copy.mesh = instance.mesh if instance.mesh.resource_path.is_empty() else instance.mesh.duplicate()
		mesh_copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_copy.custom_aabb = instance.custom_aabb
		# Материалы общие и живые (свет дня), их ставит игра при загрузке.
		mesh_copy.set_meta("receives", instance.material_override == _placeholder.vertex_material(true))
		if instance.is_in_group("shadow_caster"):
			mesh_copy.set_meta("caster", true)
		copy = mesh_copy
	elif source is CollisionShape3D:
		var shape_copy := CollisionShape3D.new()
		shape_copy.shape = (source as CollisionShape3D).shape
		copy = shape_copy
	elif source is StaticBody3D:
		copy = StaticBody3D.new()
	else:
		copy = Node3D.new()
	copy.name = source.name
	copy.transform = (source as Node3D).transform
	for child in source.get_children():
		var child_copy := _export(child, skip)
		if child_copy:
			copy.add_child(child_copy)
	return copy


func _save(scene_root: Node3D, path: String) -> void:
	var meshes := 0
	var triangles := 0
	for node in [scene_root] + scene_root.find_children("*", "", true, false):
		if node != scene_root:
			node.owner = scene_root
		if node is MeshInstance3D:
			meshes += 1
			triangles += (node as MeshInstance3D).mesh.get_faces().size() / 3
	var packed := PackedScene.new()
	packed.pack(scene_root)
	var error := ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
	var size := FileAccess.get_file_as_bytes(path).size()
	print("%s: %d models, %d triangles, %d KB%s" % [path, meshes, triangles, size / 1024,
			"" if error == OK else "  ОШИБКА %s" % error_string(error)])
	scene_root.free()
