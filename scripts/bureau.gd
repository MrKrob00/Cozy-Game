class_name Bureau
extends Interactable
## «Бюро находок» — почтовый ящик на площади. Здесь возвращают найденные
## вещи владельцам и получают за это монеты. Открывается, когда выкошена площадь.


const SHOWN_FLAG := "bureau_shown"


func _ready() -> void:
	# Почтовый ящик на столбике — своя модель (tools/make_models.py).
	Models.place(self, "mailbox", Vector3.ZERO, 1.0)
	var plot := Plot.of(self)
	if plot and not GameState.has_flag(SHOWN_FLAG):
		plot.completed.connect(_on_opened)


# Площадь выкошена — бюро открылось: камера показывает его, сообщение
# объясняет, зачем сюда приходить.
func _on_opened() -> void:
	if GameState.has_flag(SHOWN_FLAG):
		return
	GameState.set_flag(SHOWN_FLAG)
	get_tree().call_group("hud", "show_place", global_position + Vector3.UP * 0.8,
			L.t("Бюро находок открыто! Несите сюда вещи, найденные в траве, — хозяева отблагодарят монетами"))


func get_prompt() -> String:
	return "Бюро находок"


func can_interact(_player: Player) -> bool:
	var plot := Plot.of(self)
	return plot == null or plot.is_completed()


func interact(_player: Player) -> void:
	get_tree().call_group("hud", "open_bureau")
