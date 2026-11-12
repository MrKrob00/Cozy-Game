class_name Bureau
extends Interactable
## «Бюро находок» — почтовый ящик на площади. Здесь возвращают найденные
## вещи владельцам и получают за это монеты. Открывается, когда выкошена площадь.

const BLUE := Color(0.25, 0.42, 0.78)
const POST := Color(0.5, 0.36, 0.26)


func _ready() -> void:
	Placeholder.part(self, Placeholder.cylinder(0.06, 1.0), POST, Vector3(0.0, 0.5, 0.0))
	Placeholder.part(self, Placeholder.box(Vector3(0.5, 0.36, 0.34)), BLUE, Vector3(0.0, 1.15, 0.0))
	Placeholder.part(self, Placeholder.cylinder(0.17, 0.5), BLUE, Vector3(0.0, 1.33, 0.0), Vector3(0.0, 0.0, 90.0))
	Placeholder.part(self, Placeholder.box(Vector3(0.3, 0.03, 0.02)), Color(0.12, 0.16, 0.3), Vector3(0.0, 1.2, 0.18))
	Placeholder.part(self, Placeholder.box(Vector3(0.04, 0.22, 0.14)), Color(0.9, 0.3, 0.26), Vector3(0.28, 1.36, 0.0))


func get_prompt() -> String:
	return "Бюро находок"


func can_interact(_player: Player) -> bool:
	var plot := Plot.of(self)
	return plot == null or plot.is_completed()


func interact(_player: Player) -> void:
	get_tree().call_group("hud", "open_bureau")
