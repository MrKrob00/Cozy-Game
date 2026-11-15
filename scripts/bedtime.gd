class_name Bedtime
extends Interactable
## Дверь дома: лечь спать до утра. Наступает новый день, и на выкошенных
## участках отрастает короткая трава — её можно подстричь снова.
## Пока спать можно (двор выкошен), у двери светится круг.

const RING_RADIUS := 0.9

var _ring: GlowRing


func _enter_tree() -> void:
	super()
	add_to_group("bedtime")


func get_prompt() -> String:
	return "Лечь спать до утра"


func can_interact(_player: Player) -> bool:
	var plot := Plot.of(self)
	return plot == null or plot.is_completed()


func interact(_player: Player) -> void:
	get_tree().call_group("hud", "play_night")


func _process(_delta: float) -> void:
	var can_sleep := can_interact(null)
	if can_sleep and _ring == null:
		_ring = GlowRing.create(RING_RADIUS)
		_ring.name = "GlowRing"
		add_child(_ring)
	elif not can_sleep and _ring:
		_ring.vanish()
		_ring = null


## Точка, которую камера показывает, объясняя сон.
func get_show_point() -> Vector3:
	return global_position + Vector3.UP * 0.8
