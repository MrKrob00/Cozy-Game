class_name TouchPad
extends Control
## Сенсорная схема «вести пальцем»: косилка едет к точке, которой касается
## палец. Узел лежит под остальным интерфейсом и ловит касания, не попавшие
## в кнопки; игрок читает отсюда положение пальца.

## Короткое касание без движения — то же, что кнопка действия.
signal tapped

const TAP_TIME := 0.25
const TAP_DISTANCE := 24.0

## Палец на экране и его положение в координатах холста.
var held := false
var finger := Vector2.ZERO

var _index := -1
var _start := Vector2.ZERO
var _start_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _index == -1:
			_index = event.index
			held = true
			finger = event.position
			_start = finger
			_start_time = Time.get_ticks_msec() / 1000.0
		elif not event.pressed and event.index == _index:
			var quick := Time.get_ticks_msec() / 1000.0 - _start_time <= TAP_TIME
			release()
			if quick and event.position.distance_to(_start) <= TAP_DISTANCE:
				tapped.emit()
	elif event is InputEventScreenDrag and event.index == _index:
		finger = event.position


## Отпускает палец (схему сменили или открыли окно).
func release() -> void:
	held = false
	_index = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()
