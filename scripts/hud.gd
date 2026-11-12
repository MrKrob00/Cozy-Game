extends CanvasLayer
## Интерфейс прототипа: процент скошенного и подсказка управления.

@onready var _progress_label: Label = %ProgressLabel
@onready var _hint_label: Label = %HintLabel
@onready var _pinch_zoom: PinchZoom = %PinchZoom

var _hint_hidden := false


func _ready() -> void:
	var field := get_tree().get_first_node_in_group("mow_field") as MowField
	if field:
		field.progress_changed.connect(_on_progress_changed)
	_on_progress_changed(0.0)

	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		_pinch_zoom.pinch_step.connect(camera.zoom_step)

	if DisplayServer.is_touchscreen_available():
		_hint_label.text = "Коснитесь экрана и тяните, чтобы косить"
	else:
		_hint_label.text = "WASD или зажмите левую кнопку мыши, чтобы косить"

	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		player.grass_collected.connect(_on_grass_collected)


func _on_progress_changed(ratio: float) -> void:
	_progress_label.text = "Скошено: %d %%" % floori(ratio * 100.0)


func _on_grass_collected(_units: float) -> void:
	if _hint_hidden:
		return
	_hint_hidden = true
	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(_hint_label, "modulate:a", 0.0, 0.8)
