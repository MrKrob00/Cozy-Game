extends Node3D
## Россыпь бытовых мелочей (модели KayKit) у построек: бочки, ящики,
## мешки, тачка, доски. Делает места обжитыми. Трава под ними не растёт.

enum Kind { WORKSHOP, FARM, MARKET, HARVEST }

@export var kind := Kind.FARM
@export var random_seed := 1

## [модель, сдвиг (x, z), масштаб, поворот в градусах]
const LAYOUTS := {
	Kind.WORKSHOP: [
		["lumber", Vector2(0.0, 0.0), 2.6, 15.0], ["barrel", Vector2(1.3, 0.4), 4.2, 0.0],
		["wheelbarrow", Vector2(-1.4, 0.6), 4.0, -40.0], ["crate", Vector2(1.0, -0.8), 4.0, 20.0],
	],
	Kind.FARM: [
		["sack", Vector2(0.0, 0.0), 5.0, 30.0], ["sack", Vector2(0.45, 0.3), 5.0, -20.0],
		["bucket", Vector2(-0.8, 0.3), 4.5, 0.0], ["crate_open", Vector2(0.9, -0.6), 4.0, 10.0],
	],
	Kind.MARKET: [
		["barrel", Vector2(0.0, 0.0), 4.2, 0.0], ["barrel", Vector2(0.9, 0.2), 4.2, 0.0],
		["crate", Vector2(0.4, 0.9), 4.0, 35.0], ["crate", Vector2(0.4, 0.9), 3.4, 10.0],
		["pallet", Vector2(-1.1, 0.4), 4.0, 0.0], ["sack", Vector2(-1.1, 0.4), 4.5, 60.0],
	],
	Kind.HARVEST: [
		["crate_open", Vector2(0.0, 0.0), 4.0, 0.0], ["crate_open", Vector2(0.95, 0.15), 4.0, 12.0],
		["wheelbarrow", Vector2(-1.3, 0.4), 4.0, 70.0], ["barrel", Vector2(0.5, -0.9), 4.0, 0.0],
	],
}
## Высота каждой модели при масштабе 1 (чтобы ставить одно на другое).
const HEIGHTS := {"crate": 0.14, "pallet": 0.08}


func _enter_tree() -> void:
	add_to_group("grass_shaper")


func _ready() -> void:
	var stacked := {}
	for item: Array in LAYOUTS[kind]:
		var model: String = item[0]
		var offset: Vector2 = item[1]
		var lift: float = stacked.get(offset, 0.0)
		Models.place(self, model, Vector3(offset.x, lift, offset.y), item[2], deg_to_rad(item[3]))
		stacked[offset] = lift + HEIGHTS.get(model, 0.0) * item[2]


func shape_grass(field: MowField) -> void:
	field.block_circle(global_position, 1.8)
