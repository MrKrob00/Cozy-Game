class_name Bedtime
extends Interactable
## Дверь дома: лечь спать до утра. Наступает новый день, и на выкошенных
## участках отрастает короткая трава — её можно подстричь снова.


func get_prompt() -> String:
	return "Лечь спать до утра"


func can_interact(_player: Player) -> bool:
	var plot := Plot.of(self)
	return plot == null or plot.is_completed()


func interact(_player: Player) -> void:
	get_tree().call_group("hud", "play_night")
