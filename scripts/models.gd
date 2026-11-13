class_name Models
## Готовые модели KayKit (CC0, Kay Lousberg): деревья, камни, бочки, мельница.
## Переведены скриптом tools/convert_kaykit.py: цвет — в вершинах, в альфе —
## сила качания на ветру. Ставятся как детали Placeholder и склеиваются вместе
## с ними в одну модель на объект.

const DIRECTORY := "res://assets/models/"

static var _meshes: Dictionary = {}


## Модель по имени файла (без .gltf), или null.
static func mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var found: Mesh = null
	var path := DIRECTORY + model + ".gltf"
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			found = (node as MeshInstance3D).mesh
			break
		scene.free()
	_meshes[model] = found
	return found


## Ставит модель как деталь: её склеит Placeholder.bake_tree.
static func place(parent: Node3D, model: String, at: Vector3, scale: float, yaw := 0.0,
		casts_shadow := true) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh(model)
	instance.material_override = Placeholder.vertex_material()
	instance.set_meta("vertex_colors", true)
	instance.position = at
	instance.rotation.y = yaw
	instance.scale = Vector3.ONE * scale
	if not casts_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
