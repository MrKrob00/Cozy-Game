class_name Placeholder
## Временные модели из примитивов с мультяшным материалом.
## Заменяются настоящими моделями, когда они появятся.

const TOON_SHADER := preload("res://shaders/toon.gdshader")

static var _materials: Dictionary = {}


static func material(color: Color) -> ShaderMaterial:
	if _materials.has(color):
		return _materials[color]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("albedo", color)
	_materials[color] = mat
	return mat


static func part(parent: Node3D, mesh: Mesh, color: Color, position := Vector3.ZERO,
		rotation_degrees := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh


static func cylinder(radius: float, height: float, top_radius := -1.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


static func prism(size: Vector3) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	return mesh


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	return mesh
