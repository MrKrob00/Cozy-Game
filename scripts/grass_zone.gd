extends Node3D
## Зона особой травы на участке: высокая трава, бурьян или мощёная площадка.
## Узел ставится в нужное место; форма — круг (radius > 0) или прямоугольник.

enum Kind { TALL, WEEDS, PAVED }

@export var kind := Kind.WEEDS
## Радиус круга в метрах; 0 — использовать прямоугольник zone_size.
@export var radius := 2.0
## Размер прямоугольника в метрах (X, Z).
@export var zone_size := Vector2(4.0, 4.0)


func _enter_tree() -> void:
	add_to_group("grass_shaper")


func shape_grass(field: MowField) -> void:
	var circle := radius > 0.0
	match kind:
		Kind.TALL:
			# Прямоугольной высокой травы нет: хватает круга.
			field.grow_tall_circle(global_position, radius if circle else zone_size.length() * 0.5)
		Kind.WEEDS:
			if circle:
				field.grow_weeds_circle(global_position, radius)
			else:
				field.grow_weeds_rect(global_position, zone_size, global_rotation.y)
		Kind.PAVED:
			if circle:
				field.pave_circle(global_position, radius)
			else:
				field.pave_rect(global_position, zone_size, global_rotation.y)
