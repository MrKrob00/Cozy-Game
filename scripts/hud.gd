extends CanvasLayer
## Интерфейс: прогресс участка, мешок, ресурсы, контекстная кнопка,
## всплывающие сообщения, окно завершения участка и пауза.

const CREAM := Color(1.0, 0.96, 0.86)
const INK := Color(0.27, 0.22, 0.17)
const GREEN := Color(0.38, 0.64, 0.30)
const GREEN_DARK := Color(0.29, 0.52, 0.24)
const ORANGE := Color(0.95, 0.56, 0.20)
const TOAST_TIME := 3.2
## Пауза перед окном завершения участка, секунд.
const COMPLETION_DELAY := 5.0

@onready var _root: Control = %Root
@onready var _margin: MarginContainer = %Margin
@onready var _progress_label: Label = %ProgressLabel
@onready var _bag_bar: ProgressBar = %BagBar
@onready var _coins_label: Label = %CoinsLabel
@onready var _compost_label: Label = %CompostLabel
@onready var _pause_button: Button = %PauseButton
@onready var _toast: PanelContainer = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _action_button: Button = %ActionButton
@onready var _hint_label: Label = %HintLabel
@onready var _completion: Control = %Completion
@onready var _completion_title: Label = %CompletionTitle
@onready var _completion_stamps: VBoxContainer = %CompletionStamps
@onready var _completion_reward: Label = %CompletionReward
@onready var _continue_button: Button = %ContinueButton
@onready var _pause_panel: Control = %PausePanel
@onready var _pause_title: Label = %PauseTitle
@onready var _pause_stamps: VBoxContainer = %PauseStamps
@onready var _resume_button: Button = %ResumeButton
@onready var _reset_button: Button = %ResetButton
@onready var _quit_button: Button = %QuitButton
@onready var _pinch_zoom: PinchZoom = %PinchZoom

var _player: Player
var _plot: Plot
var _touch := false
var _toasts: Array[String] = []
var _toast_busy := false
var _hint_hidden := false
var _bag_pulse: Tween
var _reset_armed := false


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	_root.theme = _build_theme()
	_apply_safe_area()

	_player = get_tree().get_first_node_in_group("player") as Player
	_plot = get_tree().get_first_node_in_group("plot") as Plot
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		_pinch_zoom.pinch_step.connect(camera.zoom_step)

	if _plot:
		_plot.field.progress_changed.connect(_on_progress_changed)
		_plot.completed.connect(_on_plot_completed)
		_on_progress_changed(_plot.field.get_progress())
	if _player:
		_player.interaction_target_changed.connect(_on_target_changed)
	_on_target_changed(null)

	GameState.coins_changed.connect(_on_coins_changed)
	GameState.compost_changed.connect(_on_compost_changed)
	GameState.bag_changed.connect(_on_bag_changed)
	GameState.toast_requested.connect(show_toast)
	_on_coins_changed(GameState.coins)
	_on_compost_changed(GameState.compost)
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)

	_action_button.pressed.connect(func() -> void: _player.try_interact())
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume_button.pressed.connect(_set_paused.bind(false))
	_reset_button.pressed.connect(_on_reset_pressed)
	_quit_button.pressed.connect(func() -> void:
		GameState.save_game()
		get_tree().quit())
	_continue_button.pressed.connect(func() -> void: _completion.visible = false)
	# На телефоне и в браузере приложение закрывает система.
	_quit_button.visible = not (OS.has_feature("mobile") or OS.has_feature("web"))

	_toast.visible = false
	_completion.visible = false
	_pause_panel.visible = false
	if _touch:
		_hint_label.text = "Коснитесь экрана и тяните, чтобы косить"
	else:
		_hint_label.text = "WASD или зажмите левую кнопку мыши, чтобы косить"
	_hint_hidden = GameState.bag_fill > 0.0 or GameState.compost > 0
	_hint_label.visible = not _hint_hidden


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


## Показывает короткое сообщение; несколько подряд встают в очередь.
func show_toast(text: String) -> void:
	_toasts.append(text)
	if not _toast_busy:
		_next_toast()


func _next_toast() -> void:
	if _toasts.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	_toast_label.text = _toasts.pop_front()
	_toast.visible = true
	_toast.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tween.tween_interval(TOAST_TIME)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void:
		_toast.visible = false
		_next_toast())


func _on_progress_changed(ratio: float) -> void:
	_progress_label.text = "Скошено: %d %%" % floori(ratio * 100.0 + 0.0001)


func _on_coins_changed(value: int) -> void:
	_coins_label.text = "Монеты: %d" % value


func _on_compost_changed(value: int) -> void:
	_compost_label.text = "Компост: %d" % value


func _on_bag_changed(fill: float, capacity: float) -> void:
	_bag_bar.max_value = capacity
	_bag_bar.value = fill
	if fill > 0.0 and not _hint_hidden:
		_hint_hidden = true
		var tween := create_tween()
		tween.tween_interval(1.5)
		tween.tween_property(_hint_label, "modulate:a", 0.0, 0.8)

	# Полный мешок: полоска становится оранжевой и пульсирует.
	var full := GameState.is_bag_full()
	if full == (_bag_pulse != null):
		return
	if full:
		_bag_bar.add_theme_stylebox_override("fill", _box(ORANGE, 12))
		_bag_pulse = create_tween().set_loops()
		_bag_pulse.tween_property(_bag_bar, "modulate:a", 0.55, 0.45)
		_bag_pulse.tween_property(_bag_bar, "modulate:a", 1.0, 0.45)
	else:
		_bag_bar.remove_theme_stylebox_override("fill")
		_bag_pulse.kill()
		_bag_pulse = null
		_bag_bar.modulate.a = 1.0


func _on_target_changed(target: Interactable) -> void:
	_action_button.visible = target != null
	if target:
		_action_button.text = target.get_prompt() if _touch else "E — " + target.get_prompt()


func _on_plot_completed() -> void:
	# Сначала облёт камеры, чтобы игрок увидел выкошенный участок, потом окно.
	show_toast(_plot.completed_title)
	await get_tree().create_timer(COMPLETION_DELAY).timeout
	_completion_title.text = _plot.completed_title
	_completion_reward.text = "Награда: +%d монет" % _plot.reward_coins
	_fill_stamps(_completion_stamps)
	_completion.visible = true


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_panel.visible = paused
	_reset_armed = false
	_reset_button.text = "Начать заново"
	if paused and _plot:
		_pause_title.text = _plot.plot_name
		_fill_stamps(_pause_stamps)


func _on_reset_pressed() -> void:
	# Стирание прогресса требует второго нажатия.
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "Стереть весь прогресс? Нажмите ещё раз"
		return
	GameState.reset_game()


func _fill_stamps(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	for stamp in _plot.get_stamps():
		var label := Label.new()
		label.text = ("+  " if stamp["earned"] else "·  ") + stamp["title"]
		label.add_theme_color_override("font_color", GREEN_DARK if stamp["earned"] else INK)
		label.modulate.a = 1.0 if stamp["earned"] else 0.5
		container.add_child(label)


# На телефонах отодвигает интерфейс от вырезов и скруглений экрана.
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var window := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if window.x <= 0.0 or window.y <= 0.0 or safe.size.x <= 0.0:
		return
	var scale := _root.size / window
	const BASE := 36.0
	_margin.add_theme_constant_override("margin_left", int(BASE + safe.position.x * scale.x))
	_margin.add_theme_constant_override("margin_top", int(BASE + safe.position.y * scale.y))
	_margin.add_theme_constant_override("margin_right", int(BASE + (window.x - safe.end.x) * scale.x))
	_margin.add_theme_constant_override("margin_bottom", int(BASE + (window.y - safe.end.y) * scale.y))


func _build_theme() -> Theme:
	var ui := Theme.new()
	ui.default_font_size = 34

	var panel := _box(CREAM, 24)
	panel.set_content_margin_all(22)
	panel.border_color = Color(0.86, 0.78, 0.62)
	panel.set_border_width_all(3)
	ui.set_stylebox("panel", "PanelContainer", panel)
	ui.set_color("font_color", "Label", INK)

	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var button := _box(GREEN_DARK if state == "pressed" else GREEN, 28)
		button.set_content_margin_all(22)
		button.content_margin_left = 36
		button.content_margin_right = 36
		if state == "hover":
			button.bg_color = GREEN.lightened(0.12)
		ui.set_stylebox(state, "Button", button)
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ui.set_color(color_name, "Button", Color.WHITE)

	ui.set_stylebox("background", "ProgressBar", _box(Color(0.0, 0.0, 0.0, 0.14), 12))
	ui.set_stylebox("fill", "ProgressBar", _box(GREEN, 12))
	return ui


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
