extends CanvasLayer
## Интерфейс: прогресс участка, мешок, ресурсы, контекстная кнопка,
## всплывающие сообщения, окно завершения участка, мастерская и пауза.

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
@onready var _completion_panel: PanelContainer = %CompletionPanel
@onready var _completion_title: Label = %CompletionTitle
@onready var _completion_stamps: VBoxContainer = %CompletionStamps
@onready var _completion_reward: Label = %CompletionReward
@onready var _continue_button: Button = %ContinueButton
@onready var _pause_panel: Control = %PausePanel
@onready var _pause_window: PanelContainer = %PauseWindow
@onready var _pause_title: Label = %PauseTitle
@onready var _pause_stamps: VBoxContainer = %PauseStamps
@onready var _resume_button: Button = %ResumeButton
@onready var _sound_button: Button = %SoundButton
@onready var _graphics_button: Button = %GraphicsButton
@onready var _fps_button: Button = %FpsButton
@onready var _diag_label: Label = %DiagLabel
@onready var _fps_label: Label = %FpsLabel
@onready var _joystick: VirtualJoystick = $VirtualJoystick
@onready var _reset_button: Button = %ResetButton
@onready var _quit_button: Button = %QuitButton
@onready var _workshop_panel: Control = %WorkshopPanel
@onready var _workshop_window: PanelContainer = %WorkshopWindow
@onready var _workshop_title: Label = %WorkshopTitle
@onready var _workshop_coins: Label = %WorkshopCoins
@onready var _workshop_rows: VBoxContainer = %WorkshopRows
@onready var _workshop_close: Button = %WorkshopClose
@onready var _night: ColorRect = %Night
@onready var _night_label: Label = %NightLabel
@onready var _speech: PanelContainer = %Speech
@onready var _speech_label: Label = %SpeechLabel
@onready var _pinch_zoom: PinchZoom = %PinchZoom

var _player: Player
## Участок, прогресс которого сейчас показан.
var _plot: Plot
var _touch := false
var _toasts: Array[String] = []
var _toast_busy := false
var _hint_hidden := false
var _bag_pulse: Tween
var _reset_armed := false
var _shown_percent := -1
var _shown_coins := 0
var _shown_compost := 0
var _action_pulse: Tween
## Кто сейчас говорит (чтобы чужой уход не закрывал реплику).
var _speaker: Node
var _stamp_tweens: Array[Tween] = []
var _fps_timer := 0.0


func _enter_tree() -> void:
	add_to_group("hud")


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	_root.theme = _build_theme()
	_apply_safe_area()
	get_tree().root.size_changed.connect(_apply_safe_area)
	# Короткий тап по экрану — то же, что кнопка действия.
	_joystick.tapped.connect(_on_screen_tapped)

	_player = get_tree().get_first_node_in_group("player") as Player
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		_pinch_zoom.pinch_step.connect(camera.zoom_step)

	_toast.visible = false
	_completion.visible = false
	_pause_panel.visible = false
	_workshop_panel.visible = false
	_action_button.visible = false
	_speech.visible = false
	_night.visible = false

	for plot: Plot in get_tree().get_nodes_in_group("plot"):
		plot.completed.connect(_on_plot_completed.bind(plot))
	var village := get_tree().get_first_node_in_group("village") as Village
	if village:
		# Деревня сообщит текущий участок, когда будет готова.
		village.current_plot_changed.connect(_show_plot)
		village.festival_started.connect(_on_festival_started.bind(village))
	else:
		_show_plot(get_tree().get_first_node_in_group("plot") as Plot)
	if _player:
		_player.interaction_target_changed.connect(_on_target_changed)

	_shown_coins = GameState.coins
	_shown_compost = GameState.compost
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.compost_changed.connect(_on_compost_changed)
	GameState.bag_changed.connect(_on_bag_changed)
	GameState.toast_requested.connect(show_toast)
	GameState.settings_changed.connect(_update_settings_buttons)
	_on_coins_changed(GameState.coins)
	_on_compost_changed(GameState.compost)
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)

	_action_button.pressed.connect(func() -> void: _player.try_interact())
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume_button.pressed.connect(_set_paused.bind(false))
	_sound_button.pressed.connect(func() -> void:
		GameState.set_sound_enabled(not GameState.sound_enabled)
		_update_settings_buttons())
	_graphics_button.pressed.connect(func() -> void:
		GameState.set_graphics_quality((GameState.get_quality() + 1) % Graphics.PRESETS.size())
		_update_settings_buttons())
	_fps_button.pressed.connect(func() -> void:
		GameState.set_show_fps(not GameState.show_fps)
		_update_settings_buttons())
	_reset_button.pressed.connect(_on_reset_pressed)
	_quit_button.pressed.connect(func() -> void:
		GameState.save_game()
		get_tree().quit())
	_continue_button.pressed.connect(func() -> void:
		_completion.visible = false
		_continue_button.text = "Косить дальше")
	_workshop_close.pressed.connect(close_workshop)
	# На телефоне и в браузере приложение закрывает система.
	_quit_button.visible = not (OS.has_feature("mobile") or OS.has_feature("web"))
	_update_settings_buttons()
	for button: Button in [_action_button, _pause_button, _resume_button, _sound_button,
			_graphics_button, _fps_button, _reset_button, _quit_button, _continue_button,
			_workshop_close]:
		button.pressed.connect(_on_any_button_pressed.bind(button))

	if _touch:
		_hint_label.text = "Коснитесь экрана и тяните, чтобы косить"
	else:
		_hint_label.text = "WASD или зажмите левую кнопку мыши, чтобы косить"
	_hint_hidden = GameState.bag_fill > 0.0 or GameState.grass_banked > 0.0
	_hint_label.visible = not _hint_hidden


func _process(delta: float) -> void:
	# Счётчик FPS и диагностика обновляются пару раз в секунду.
	_fps_timer -= delta
	if _fps_timer > 0.0:
		return
	_fps_timer = 0.5
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _pause_panel.visible:
		_diag_label.text = _diagnostics()


func _input(event: InputEvent) -> void:
	# Кнопки Godot слышат только первый палец. Если левый палец держит джойстик,
	# нажатие вторым пальцем на кнопку действия ловим сами.
	if event is InputEventScreenTouch and event.pressed and event.index > 0 \
			and _action_button.visible and not get_tree().paused \
			and _action_button.get_global_rect().has_point(event.position):
		_action_button.pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if _workshop_panel.visible:
			close_workshop()
		else:
			_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


## Показывает короткое сообщение; несколько подряд встают в очередь.
func show_toast(text: String) -> void:
	_toasts.append(text)
	if not _toast_busy:
		_next_toast()


## Открывает мастерскую (вызывается объектом Workshop через группу «hud»).
func open_workshop() -> void:
	_open_window(_fill_workshop)


## Открывает «Бюро находок» (вызывается объектом Bureau через группу «hud»).
func open_bureau() -> void:
	_open_window(_fill_bureau)


## Ночь: экран темнеет, наступает новый день, экран светлеет.
func play_night() -> void:
	if _night.visible:
		return
	get_tree().paused = true
	_night.visible = true
	_night.modulate.a = 0.0
	_night_label.modulate.a = 0.0
	_night_label.text = "День %d" % (GameState.day + 1)
	var tween := create_tween()
	tween.tween_property(_night, "modulate:a", 1.0, 0.7)
	tween.tween_callback(GameState.next_day)
	tween.tween_property(_night_label, "modulate:a", 1.0, 0.4)
	tween.tween_interval(1.1)
	tween.tween_callback(func() -> void:
		Sfx.play("chirp_1", -6.0)
		Sfx.play("chirp_3", -8.0))
	tween.tween_property(_night, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func() -> void:
		_night.visible = false
		get_tree().paused = false
		show_toast("Доброе утро! На выкошенных участках подросла трава"))


# Окно со списком (мастерская, бюро находок): игра на паузе, пока оно открыто.
func _open_window(fill: Callable) -> void:
	get_tree().paused = true
	fill.call()
	_workshop_panel.visible = true
	Juice.pop_in(_workshop_window, 0.25)
	Sfx.play("pop")


func close_workshop() -> void:
	_workshop_panel.visible = false
	get_tree().paused = false


## Показывает реплику жителя внизу экрана (вызывается через группу «hud»).
func show_speech(speaker: Node, speaker_name: String, text: String) -> void:
	_speaker = speaker
	_speech_label.text = "%s: %s" % [speaker_name, text]
	Juice.pop_in(_speech, 0.22)


func hide_speech(speaker: Node) -> void:
	if speaker == _speaker:
		_speaker = null
		_speech.visible = false


func _next_toast() -> void:
	if _toasts.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	_toast_label.text = _toasts.pop_front()
	Juice.pop_in(_toast)
	var tween := create_tween()
	tween.tween_interval(TOAST_TIME)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void:
		_toast.visible = false
		_next_toast())


# Переключает панель прогресса на другой участок.
func _show_plot(plot: Plot) -> void:
	if plot == _plot or plot == null:
		return
	if _plot:
		_plot.field.progress_changed.disconnect(_on_progress_changed)
	var first := _plot == null
	_plot = plot
	_plot.field.progress_changed.connect(_on_progress_changed)
	_shown_percent = -1
	_on_progress_changed(_plot.get_progress())
	if not first:
		Juice.punch(_progress_label, 0.15)


func _on_progress_changed(ratio: float) -> void:
	var percent := floori(ratio * 100.0 + 0.0001)
	if percent == _shown_percent:
		return
	_progress_label.text = "%s: %d %%" % [_plot.plot_name, percent]
	# Каждый новый процент слегка «подпрыгивает», круглые — сильнее.
	if _shown_percent >= 0:
		Juice.punch(_progress_label, 0.22 if percent % 10 == 0 else 0.08)
	_shown_percent = percent


func _on_coins_changed(value: int) -> void:
	_coins_label.text = "Монеты: %d" % value
	if value != _shown_coins:
		Juice.punch(_coins_label, 0.3)
	_shown_coins = value


func _on_compost_changed(value: int) -> void:
	_compost_label.text = "Компост: %d" % value
	if value != _shown_compost:
		Juice.punch(_compost_label, 0.3)
	_shown_compost = value


func _on_bag_changed(fill: float, capacity: float) -> void:
	_bag_bar.max_value = capacity
	_bag_bar.value = fill
	if fill > 0.0 and not _hint_hidden:
		_hint_hidden = true
		var tween := create_tween()
		tween.tween_interval(1.5)
		tween.tween_property(_hint_label, "modulate:a", 0.0, 0.8)
		tween.tween_callback(_hint_label.hide)

	# Полный мешок: полоска становится оранжевой и пульсирует.
	var full := GameState.is_bag_full()
	if full == (_bag_pulse != null):
		return
	if full:
		_bag_bar.add_theme_stylebox_override("fill", _box(ORANGE, 12))
		_bag_pulse = create_tween().set_loops()
		_bag_pulse.tween_property(_bag_bar, "modulate:a", 0.55, 0.45)
		_bag_pulse.tween_property(_bag_bar, "modulate:a", 1.0, 0.45)
		Juice.punch(_bag_bar, 0.25)
		Sfx.play("bag_full")
		Sfx.buzz(40)
	else:
		_bag_bar.remove_theme_stylebox_override("fill")
		_bag_pulse.kill()
		_bag_pulse = null
		_bag_bar.modulate.a = 1.0


func _on_target_changed(target: Interactable) -> void:
	if _action_pulse:
		_action_pulse.kill()
		_action_pulse = null
	if target == null:
		_action_button.visible = false
		return
	_action_button.text = target.get_prompt() if _touch else "E — " + target.get_prompt()
	Juice.pop_in(_action_button)
	Sfx.play("pop", -8.0)
	# Кнопка мягко «дышит», чтобы её заметили.
	_action_pulse = create_tween().set_loops()
	_action_pulse.tween_interval(0.35)
	_action_pulse.tween_property(_action_button, "scale", Vector2.ONE * 1.05, 0.5) \
			.set_trans(Tween.TRANS_SINE)
	_action_pulse.tween_property(_action_button, "scale", Vector2.ONE, 0.5) \
			.set_trans(Tween.TRANS_SINE)


func _on_plot_completed(plot: Plot) -> void:
	# Сначала облёт камеры, чтобы игрок увидел выкошенный участок, потом окно.
	show_toast(plot.completed_title)
	await get_tree().create_timer(COMPLETION_DELAY).timeout
	_completion_title.text = plot.completed_title
	_completion_reward.text = "Награда: +%d монет" % plot.reward_coins
	_kill_stamp_tweens()
	var stamps := _fill_stamps(_completion_stamps, plot)
	_completion.visible = true
	Juice.pop_in(_completion_panel, 0.4)
	Sfx.play("pop")
	# Штампы появляются по одному.
	for i in stamps.size():
		var stamp := stamps[i]
		var shown_alpha := stamp.modulate.a
		stamp.modulate.a = 0.0
		var tween := create_tween()
		_stamp_tweens.append(tween)
		tween.tween_interval(0.45 + 0.28 * i)
		tween.tween_callback(func() -> void:
			# Окно могло перезаполниться, пока шла анимация.
			if not is_instance_valid(stamp):
				return
			stamp.modulate.a = shown_alpha
			Juice.punch(stamp, 0.25)
			if shown_alpha > 0.9:
				Sfx.play("coin", -8.0, 0.9 + 0.08 * i, 0.0))


func _kill_stamp_tweens() -> void:
	for tween in _stamp_tweens:
		if tween.is_valid():
			tween.kill()
	_stamp_tweens.clear()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_panel.visible = paused
	_reset_armed = false
	_reset_button.text = "Начать заново"
	if paused and _plot:
		_pause_title.text = _plot.plot_name
		_fill_stamps(_pause_stamps, _plot)
		Juice.pop_in(_pause_window, 0.22)


func _on_reset_pressed() -> void:
	# Стирание прогресса требует второго нажатия.
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "Стереть весь прогресс? Нажмите ещё раз"
		return
	GameState.reset_game()


func _on_any_button_pressed(button: Button) -> void:
	Sfx.play("click")
	Juice.punch(button, 0.08, 0.2)


func _on_screen_tapped() -> void:
	if _player and _player.interaction_target and not get_tree().paused:
		_action_button.pressed.emit()


func _update_settings_buttons() -> void:
	_sound_button.text = "Звук: включён" if GameState.sound_enabled else "Звук: выключен"
	_graphics_button.text = "Графика: %s" % Graphics.preset["title"]
	_fps_button.text = "Счётчик FPS: включён" if GameState.show_fps else "Счётчик FPS: выключен"
	_fps_label.visible = GameState.show_fps


# Сведения об устройстве: помогают разобраться, если на телефоне что-то не так.
func _diagnostics() -> String:
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	return "%d FPS · окно %d×%d · холст %d×%d · безопасная область %d,%d %d×%d · %s · %s · графика: %s" % [
		Engine.get_frames_per_second(), window.x, window.y, int(_root.size.x), int(_root.size.y),
		safe.position.x, safe.position.y, safe.size.x, safe.size.y,
		OS.get_model_name(), RenderingServer.get_video_adapter_name(), Graphics.preset["title"]]


func _fill_stamps(container: VBoxContainer, plot: Plot) -> Array[Label]:
	for child in container.get_children():
		child.queue_free()
	var labels: Array[Label] = []
	for stamp in plot.get_stamps():
		var label := Label.new()
		label.text = ("+  " if stamp["earned"] else "·  ") + stamp["title"]
		label.add_theme_color_override("font_color", GREEN_DARK if stamp["earned"] else INK)
		label.modulate.a = 1.0 if stamp["earned"] else 0.5
		container.add_child(label)
		labels.append(label)
	return labels


# Финал: все участки выкошены. Окно с итогами показывается один раз.
func _on_festival_started(announce: bool, village: Village) -> void:
	if not announce:
		return
	show_toast("Деревня ожила! Сегодня праздник")
	await get_tree().create_timer(3.0).timeout
	_kill_stamp_tweens()
	_completion_title.text = "Деревня ожила!"
	_completion_reward.text = "Спасибо за игру! Косить можно и дальше"
	for child in _completion_stamps.get_children():
		child.queue_free()
	for line in village.get_summary():
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_completion_stamps.add_child(label)
	_continue_button.text = "Остаться в деревне"
	_completion.visible = true
	Juice.pop_in(_completion_panel, 0.4)
	Sfx.play("pop")


# Строки бюро находок: найденные вещи, у которых есть владелец.
func _fill_bureau() -> void:
	for child in _workshop_rows.get_children():
		child.queue_free()
	_workshop_title.text = "Бюро находок"
	var finds := get_tree().get_nodes_in_group("find")
	var found := finds.filter(func(find: FindItem) -> bool: return find.is_collected()).size()
	_workshop_coins.text = "Найдено вещей: %d из %d · Монеты: %d" % [found, finds.size(), GameState.coins]
	var listed := 0
	for find: FindItem in finds:
		if find.owner_name == "" or not find.is_collected():
			continue
		listed += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 28)
		_workshop_rows.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := Label.new()
		title.text = find.display_name.left(1).to_upper() + find.display_name.substr(1)
		text.add_child(title)
		var about := Label.new()
		about.add_theme_font_size_override("font_size", 28)
		about.modulate.a = 0.7
		about.text = "Владелец: %s" % find.owner_name
		text.add_child(about)
		if find.is_returned():
			var done := Label.new()
			done.text = "Возвращено"
			done.add_theme_color_override("font_color", GREEN_DARK)
			done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(done)
			continue
		var give := Button.new()
		give.text = "Вернуть · +%d" % find.return_reward
		give.focus_mode = Control.FOCUS_NONE
		give.custom_minimum_size = Vector2(280.0, 0.0)
		give.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		give.pressed.connect(_on_return_pressed.bind(find))
		row.add_child(give)
	if listed == 0:
		var empty := Label.new()
		empty.text = "Пока нечего возвращать. Чужие вещи прячутся в траве"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.7
		_workshop_rows.add_child(empty)


func _on_return_pressed(find: FindItem) -> void:
	find.give_back()
	Sfx.play("coin")
	Sfx.buzz(25)
	if find.thanks != "":
		show_toast("%s: %s" % [find.owner_name, find.thanks])
	_fill_bureau()
	Juice.punch(_workshop_coins, 0.2)


# Строки мастерской: по одной на апгрейд, с ценой следующего уровня.
func _fill_workshop() -> void:
	for child in _workshop_rows.get_children():
		child.queue_free()
	_workshop_title.text = "Мастерская"
	_workshop_coins.text = "Монеты: %d" % GameState.coins
	for id: String in GameState.UPGRADES:
		var info: Dictionary = GameState.UPGRADES[id]
		var level := GameState.upgrade_level(id)
		var values: Array = info["values"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 28)
		_workshop_rows.add_child(row)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var title := Label.new()
		title.text = "%s — уровень %d из %d" % [info["title"], level + 1, values.size()]
		text.add_child(title)
		var about := Label.new()
		about.add_theme_font_size_override("font_size", 28)
		about.modulate.a = 0.7
		if GameState.is_upgrade_maxed(id):
			about.text = "%s: %s %s" % [info["about"], _number(values[level]), info["unit"]]
		else:
			about.text = "%s: %s → %s %s" % [info["about"], _number(values[level]),
					_number(values[level + 1]), info["unit"]]
		text.add_child(about)

		if GameState.is_upgrade_maxed(id):
			var done := Label.new()
			done.text = "Максимум"
			done.add_theme_color_override("font_color", GREEN_DARK)
			done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(done)
			continue
		var cost := GameState.upgrade_cost(id)
		var buy := Button.new()
		buy.text = "%d монет" % cost
		buy.focus_mode = Control.FOCUS_NONE
		buy.custom_minimum_size = Vector2(240.0, 0.0)
		buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Недоступную покупку приглушаем, но нажать можно — игра объяснит звуком.
		buy.modulate.a = 1.0 if GameState.coins >= cost else 0.5
		buy.pressed.connect(_on_buy_pressed.bind(id, buy))
		row.add_child(buy)


func _on_buy_pressed(id: String, button: Button) -> void:
	if not GameState.buy_upgrade(id):
		Sfx.play("deny")
		Juice.punch(_workshop_coins, 0.25)
		Juice.punch(button, 0.06, 0.2)
		return
	Sfx.play("coin")
	Sfx.play("plant", -6.0)
	Sfx.buzz(30)
	_fill_workshop()
	Juice.punch(_workshop_coins, 0.25)


# Число для показа: целое без дроби, дробное с запятой.
func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return ("%.1f" % value).replace(".", ",")


# На телефонах отодвигает интерфейс от вырезов и скруглений экрана.
func _apply_safe_area() -> void:
	var insets: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if OS.has_feature("mobile"):
		insets = safe_insets(Vector2(DisplayServer.window_get_size()),
				Rect2(DisplayServer.get_display_safe_area()), _root.size)
	const BASE := 36.0
	var names := ["margin_left", "margin_top", "margin_right", "margin_bottom"]
	for i in names.size():
		_margin.add_theme_constant_override(names[i], int(BASE + insets[i]))


## Отступы безопасной области в единицах интерфейса: слева, сверху, справа, снизу.
## Устройство может сообщить область в чужих координатах (например, для другой
## ориентации экрана). Такие значения отбрасываются: иначе интерфейс уедет за край.
static func safe_insets(window: Vector2, safe: Rect2, canvas: Vector2) -> Array[float]:
	var insets: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if window.x <= 0.0 or window.y <= 0.0 or canvas.x <= 0.0 or canvas.y <= 0.0:
		return insets
	var scale := canvas / window
	var raw: Array[float] = [
		safe.position.x * scale.x,
		safe.position.y * scale.y,
		(window.x - safe.end.x) * scale.x,
		(window.y - safe.end.y) * scale.y,
	]
	# Вырез или скругление не бывает больше восьмой части экрана.
	var limits: Array[float] = [canvas.x * 0.12, canvas.y * 0.12, canvas.x * 0.12, canvas.y * 0.12]
	for i in raw.size():
		if raw[i] > 0.0 and raw[i] <= limits[i]:
			insets[i] = raw[i]
	return insets


func _build_theme() -> Theme:
	var ui := Theme.new()
	ui.default_font_size = 34

	var panel := _box(CREAM, 24)
	panel.set_content_margin_all(22)
	panel.border_color = Color(0.86, 0.78, 0.62)
	panel.set_border_width_all(3)
	panel.shadow_color = Color(0.2, 0.15, 0.1, 0.18)
	panel.shadow_size = 8
	panel.shadow_offset = Vector2(0.0, 4.0)
	ui.set_stylebox("panel", "PanelContainer", panel)
	ui.set_color("font_color", "Label", INK)

	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var button := _box(GREEN_DARK if state == "pressed" else GREEN, 28)
		button.set_content_margin_all(22)
		button.content_margin_left = 36
		button.content_margin_right = 36
		# «Толстая» нижняя кромка; при нажатии кнопка проседает.
		button.border_color = GREEN_DARK.darkened(0.15)
		button.border_width_bottom = 2 if state == "pressed" else 8
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
