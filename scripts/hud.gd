extends CanvasLayer
## Интерфейс: прогресс участка, мешок, ресурсы, контекстная кнопка,
## всплывающие сообщения, окно завершения участка, мастерская и пауза.

const CREAM := Color(1.0, 0.96, 0.86)
const INK := Color(0.27, 0.22, 0.17)
const GREEN := Color(0.38, 0.64, 0.30)
const GREEN_DARK := Color(0.29, 0.52, 0.24)
const ORANGE := Color(0.95, 0.56, 0.20)
const TOAST_TIME := 3.2
const TOAST_TIME_BUSY := 1.7
const MAX_WAITING_TOASTS := 2
## Пауза перед окном завершения участка, секунд.
const COMPLETION_DELAY := 5.0
## Сколько летят значки награды до счётчика, секунд.
const FLIGHT_TIME := 0.85
## Секунд на букву в реплике жителя.
const TYPE_SPEED := 0.028
## Пауза между «скошено 80 %» и показом новой калитки, секунд.
const REVEAL_DELAY := 0.7
## Где в своей части экрана стоит закреплённый джойстик (доли ширины и высоты).
const FIXED_STICK_AT := Vector2(0.36, 0.62)

@onready var _root: Control = %Root
@onready var _margin: MarginContainer = %Margin
@onready var _progress_label: Label = %ProgressLabel
@onready var _plot_bar: ProgressBar = %PlotBar
@onready var _flyers: Control = %Flyers
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
@onready var _music_button: Button = %MusicButton
@onready var _graphics_button: Button = %GraphicsButton
@onready var _fps_button: Button = %FpsButton
@onready var _diag_label: Label = %DiagLabel
@onready var _fps_label: Label = %FpsLabel
@onready var _joystick: VirtualJoystick = $VirtualJoystick
@onready var _controls_button: Button = %ControlsButton
@onready var _probe_button: Button = %ProbeButton
@onready var _language_button: Button = %LanguageButton
@onready var _title_language_button: Button = %TitleLanguageButton
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
@onready var _title_panel: Control = %TitlePanel
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle: Label = %Subtitle
@onready var _play_button: Button = %PlayButton
@onready var _new_game_button: Button = %NewGameButton

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
# Числа, которые сейчас показаны на счётчиках (они досчитываются плавно).
var _shown_coins := 0
var _shown_compost := 0
var _counter_tweens: Dictionary = {}
# Сколько значков награды ещё летит к каждому счётчику.
var _in_flight: Dictionary = {"coins": 0, "compost": 0}
var _bar_tween: Tween
var _speech_tween: Tween
var _action_pulse: Tween
## Кто сейчас говорит (чтобы чужой уход не закрывал реплику).
var _speaker: Node
var _stamp_tweens: Array[Tween] = []
var _fps_timer := 0.0
var _new_game_armed := false
var _title_bob: Tween
var _touch_pad: TouchPad
var _goal_mark: ColorRect
## Показывать ли новую калитку камерой сразу, как она открылась (в проверках
## и при съёмке трейлера это выключают и показывают сами).
var auto_reveal := true
var _revealing := false
## Замер кадра (FrameProbe), если он идёт сейчас.
var _probe: FrameProbe
## Игра идёт (не титульный экран): сенсорное управление включено.
var _controls_live := true


func _enter_tree() -> void:
	add_to_group("hud")


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	_root.theme = _build_theme()
	_apply_safe_area()
	get_tree().root.size_changed.connect(_apply_safe_area)
	# Короткий тап по экрану — то же, что кнопка действия.
	_joystick.tapped.connect(_on_screen_tapped)
	# Схема «вести пальцем»: свой слой касаний на месте джойстика.
	_touch_pad = TouchPad.new()
	_touch_pad.name = "TouchPad"
	_touch_pad.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_touch_pad)
	move_child(_touch_pad, _joystick.get_index())
	_touch_pad.tapped.connect(_on_screen_tapped)
	GameState.settings_changed.connect(_apply_touch_controls)
	_apply_touch_controls()

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
		plot.next_opened.connect(_on_next_opened)
		plot.milestone.connect(_on_milestone.bind(plot))
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
	GameState.reward_shown.connect(_on_reward_shown)
	GameState.settings_changed.connect(_update_settings_buttons)
	_coins_label.text = L.t("Монеты: %d") % _shown_coins
	_compost_label.text = L.t("Компост: %d") % _shown_compost
	_on_bag_changed(GameState.bag_fill, GameState.bag_capacity)

	_action_button.pressed.connect(func() -> void: _player.try_interact())
	_pause_button.pressed.connect(_set_paused.bind(true))
	_resume_button.pressed.connect(_set_paused.bind(false))
	_sound_button.pressed.connect(func() -> void:
		GameState.set_sound_enabled(not GameState.sound_enabled)
		_update_settings_buttons())
	_music_button.pressed.connect(func() -> void:
		GameState.set_music_enabled(not GameState.music_enabled)
		_update_settings_buttons())
	_graphics_button.pressed.connect(func() -> void:
		GameState.set_graphics_quality((GameState.get_quality() + 1) % Graphics.PRESETS.size())
		_update_settings_buttons())
	_fps_button.pressed.connect(func() -> void:
		GameState.set_show_fps(not GameState.show_fps)
		_update_settings_buttons())
	_controls_button.pressed.connect(func() -> void:
		GameState.set_touch_controls(GameState.touch_controls + 1)
		_update_settings_buttons())
	# Кнопки паузы стоят в два столбца одинаковой ширины: одним столбцом
	# они не помещались по высоте экрана.
	for child in _resume_button.get_parent().get_children():
		(child as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_probe_button.pressed.connect(_run_probe)
	for button: Button in [_language_button, _title_language_button]:
		button.pressed.connect(_switch_language)
	# Выбор сенсорной схемы нужен только там, где есть сенсорный экран.
	_controls_button.visible = _touch
	_reset_button.pressed.connect(_on_reset_pressed)
	_quit_button.pressed.connect(func() -> void:
		GameState.save_game()
		get_tree().quit())
	_continue_button.pressed.connect(func() -> void:
		_completion.visible = false
		_continue_button.text = "Косить дальше")
	# Окно завершения закрыто — показываем, какая калитка открылась.
	_completion.visibility_changed.connect(func() -> void:
		if not _completion.visible:
			_reveal_next_plot())
	_workshop_close.pressed.connect(close_workshop)
	# На телефоне и в браузере приложение закрывает система.
	_quit_button.visible = not (OS.has_feature("mobile") or OS.has_feature("web"))
	_update_settings_buttons()
	for button: Button in [_action_button, _pause_button, _resume_button, _sound_button,
			_music_button, _graphics_button, _fps_button, _controls_button, _probe_button, _language_button,
			_title_language_button, _reset_button, _quit_button, _continue_button,
			_workshop_close]:
		button.pressed.connect(_on_any_button_pressed.bind(button))

	if _touch:
		_hint_label.text = "Ведите джойстиком слева, чтобы косить"
	else:
		_hint_label.text = "WASD или зажмите левую кнопку мыши, чтобы косить"
	_hint_hidden = GameState.bag_fill > 0.0 or GameState.grass_banked > 0.0
	_hint_label.visible = not _hint_hidden

	var pointer := GoalPointer.new()
	pointer.name = "GoalPointer"
	_root.add_child(pointer)
	_root.move_child(pointer, _flyers.get_index())

	_play_button.pressed.connect(_on_play_pressed)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	for button: Button in [_play_button, _new_game_button]:
		button.pressed.connect(_on_any_button_pressed.bind(button))
	# Титульный экран — один раз за запуск; в проверках без экрана его нет.
	if GameState.title_seen or DisplayServer.get_name() == "headless":
		_title_panel.visible = false
	else:
		_show_title.call_deferred()


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
	if _probe and _probe.status != "":
		_toast_label.text = _probe.status
		_toast.visible = true


func is_title_shown() -> bool:
	return _title_panel.visible


# Титульный экран: камера кружит над деревней, игрок ждёт.
func _show_title() -> void:
	_title_panel.visible = true
	_margin.visible = false
	_controls_live = false
	_apply_touch_controls()
	if _player:
		_player.controls_enabled = false
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		camera.set_menu(true)
	var returning := GameState.has_progress()
	_play_button.text = "Продолжить" if returning else "Играть"
	_new_game_button.visible = returning
	_new_game_button.text = "Новая игра"
	_new_game_armed = false
	# Название падает сверху, подпись и кнопки появляются следом.
	Juice.slam(_title_label, 1.5, 0.3)
	var appear: Array[Control] = [_subtitle, _play_button]
	if returning:
		appear.append(_new_game_button)
	for i in appear.size():
		var control := appear[i]
		control.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.35 + 0.15 * i)
		tween.tween_callback(func() -> void: Juice.pop_in(control, 0.3))
	if _title_bob:
		_title_bob.kill()
	_title_bob = create_tween().set_loops()
	_title_bob.tween_property(_title_label, "rotation", 0.02, 1.6).set_trans(Tween.TRANS_SINE)
	_title_bob.tween_property(_title_label, "rotation", -0.02, 1.6).set_trans(Tween.TRANS_SINE)


func _on_play_pressed() -> void:
	GameState.title_seen = true
	if _title_bob:
		_title_bob.kill()
	var fade := create_tween()
	fade.tween_property(_title_panel, "modulate:a", 0.0, 0.35)
	fade.tween_callback(func() -> void:
		_title_panel.visible = false
		_title_panel.modulate.a = 1.0)
	var camera := get_viewport().get_camera_3d() as FollowCamera
	if camera:
		camera.set_menu(false)
	if _player:
		_player.controls_enabled = true
	_controls_live = true
	_apply_touch_controls()
	_margin.visible = true
	Juice.pop_in(_margin, 0.35)
	Sfx.play("chime", -8.0)


func _on_new_game_pressed() -> void:
	# Стирание прогресса требует второго нажатия.
	if not _new_game_armed:
		_new_game_armed = true
		_new_game_button.text = "Стереть прогресс? Нажмите ещё раз"
		return
	GameState.title_seen = true
	GameState.reset_game()


func _input(event: InputEvent) -> void:
	if _title_panel.visible:
		# На титульном экране пауза не открывается.
		return
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
	# Очередь короткая: если сообщений накопилось, старые уже не ко времени.
	while _toasts.size() >= MAX_WAITING_TOASTS:
		_toasts.pop_front()
	_toasts.append(L.t(text))
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
	_night_label.text = L.t("День %d") % (GameState.day + 1)
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
	speaker_name = L.t(speaker_name)
	_speech_label.text = "%s: %s" % [speaker_name, L.t(text)]
	_speech_label.visible_characters = speaker_name.length() + 2
	Juice.pop_in(_speech, 0.22)
	# У каждого жителя свой голос: высота «бипа» зависит от имени.
	var pitch := 0.8 + float(hash(speaker_name) % 50) / 100.0
	if _speech_tween:
		_speech_tween.kill()
	_speech_tween = create_tween()
	var total := _speech_label.get_total_character_count()
	_speech_tween.tween_method(_type_speech.bind(pitch), float(speaker_name.length() + 2), float(total),
			(total - speaker_name.length()) * TYPE_SPEED)


func _type_speech(characters: float, pitch: float) -> void:
	var count := int(characters)
	if count == _speech_label.visible_characters:
		return
	_speech_label.visible_characters = count
	if count % 3 == 0 and count < _speech_label.get_total_character_count():
		Sfx.play("blip", -16.0, pitch, 0.08)


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
	# Если следом ждут другие, это сообщение висит меньше.
	tween.tween_interval(TOAST_TIME if _toasts.is_empty() else TOAST_TIME_BUSY)
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
	if _bar_tween:
		_bar_tween.kill()
	_plot_bar.value = _plot.get_progress()
	_update_goal_mark()
	if not first:
		Juice.punch(_progress_label, 0.15)


# Отметка на полосе прогресса: докуда косить, чтобы открылся следующий участок.
func _update_goal_mark() -> void:
	if _goal_mark == null:
		_goal_mark = ColorRect.new()
		_goal_mark.name = "GoalMark"
		_goal_mark.color = Color(1.0, 0.80, 0.25)
		_goal_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plot_bar.add_child(_goal_mark)
	_goal_mark.visible = _plot != null and _plot.has_next_to_open()
	if _goal_mark.visible:
		_goal_mark.anchor_left = _plot.open_next_at
		_goal_mark.anchor_right = _plot.open_next_at
		_goal_mark.anchor_top = 0.0
		_goal_mark.anchor_bottom = 1.0
		_goal_mark.offset_left = -3.0
		_goal_mark.offset_right = 3.0
		_goal_mark.offset_top = -5.0
		_goal_mark.offset_bottom = 5.0


func _on_progress_changed(ratio: float) -> void:
	var percent := floori(ratio * 100.0 + 0.0001)
	if percent == _shown_percent:
		return
	_progress_label.text = "%s: %d %%" % [L.t(_plot.plot_name), percent]
	# Каждый новый процент слегка «подпрыгивает», круглые — сильнее.
	if _shown_percent >= 0:
		Juice.punch(_progress_label, 0.22 if percent % 10 == 0 else 0.08)
		# Полоса догоняет плавно.
		if _bar_tween:
			_bar_tween.kill()
		_bar_tween = create_tween()
		_bar_tween.tween_property(_plot_bar, "value", ratio, 0.35) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shown_percent = percent


func _on_milestone(percent: int, plot: Plot) -> void:
	var words := {25: "четверть позади", 50: "половина!", 75: "осталось чуть-чуть"}
	show_toast("%s: %s" % [L.t(plot.plot_name), L.t(words.get(percent, "%d %%" % percent))])
	Sfx.play("chime", -4.0, 1.0 + (percent - 25) / 200.0, 0.0)
	Sfx.buzz(20)
	if plot == _plot:
		Juice.punch(_plot_bar, 0.3, 0.4)


# Счётчики меняются кадром позже: если в этом кадре награда вылетела из мира,
# счётчик подождёт, пока значки долетят, и только потом досчитает.
func _on_coins_changed(_value: int) -> void:
	_update_counter.call_deferred("coins")


func _on_compost_changed(_value: int) -> void:
	_update_counter.call_deferred("compost")


func _update_counter(kind: String) -> void:
	var label := _coins_label if kind == "coins" else _compost_label
	var target := GameState.coins if kind == "coins" else GameState.compost
	var shown := _shown_coins if kind == "coins" else _shown_compost
	if target == shown:
		return
	var delay := FLIGHT_TIME if _in_flight[kind] > 0 else 0.0
	if _counter_tweens.has(kind):
		_counter_tweens[kind].kill()
	var tween := create_tween()
	_counter_tweens[kind] = tween
	tween.tween_interval(delay)
	tween.tween_method(_show_counter.bind(kind), float(shown), float(target),
			clampf(absf(target - shown) * 0.02, 0.25, 0.8)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if delay == 0.0:
		Juice.punch(label, 0.3)


func _show_counter(value: float, kind: String) -> void:
	var number := roundi(value)
	if kind == "coins":
		_shown_coins = number
		_coins_label.text = L.t("Монеты: %d") % number
	else:
		_shown_compost = number
		_compost_label.text = L.t("Компост: %d") % number


# Награда вылетает из точки мира и летит к своему счётчику горстью значков.
func _on_reward_shown(kind: String, amount: int, world_position: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or amount <= 0 or camera.is_position_behind(world_position):
		return
	var label := _coins_label if kind == "coins" else _compost_label
	var start := camera.unproject_position(world_position)
	var target := label.get_global_rect().get_center() - Vector2.ONE * RewardIcon.SIZE * 0.5
	var count := clampi(int(sqrt(float(amount))) + 1, 2, 9)
	_in_flight[kind] += count
	for i in count:
		var icon := RewardIcon.new()
		icon.kind = RewardIcon.Kind.COIN if kind == "coins" else RewardIcon.Kind.LEAF
		_flyers.add_child(icon)
		var from := start - Vector2.ONE * RewardIcon.SIZE * 0.5
		var burst := from + Vector2(randf_range(-90.0, 90.0), randf_range(-110.0, -30.0))
		icon.position = from
		icon.scale = Vector2.ONE * 0.3
		var tween := icon.create_tween()
		# Сначала разлетаются горстью, потом по очереди летят к счётчику.
		tween.set_parallel(true)
		tween.tween_property(icon, "position", burst, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(icon, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.set_parallel(false)
		tween.tween_interval(0.05 + 0.05 * i)
		tween.tween_property(icon, "position", target, FLIGHT_TIME - 0.27 - 0.05 * i) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(icon, "scale", Vector2.ONE * 0.6, FLIGHT_TIME - 0.27 - 0.05 * i)
		tween.tween_callback(_on_icon_arrived.bind(icon, kind, label, i))


func _on_icon_arrived(icon: RewardIcon, kind: String, label: Label, index: int) -> void:
	icon.queue_free()
	_in_flight[kind] = maxi(_in_flight[kind] - 1, 0)
	Juice.punch(label, 0.18, 0.2)
	Sfx.play("coin" if kind == "coins" else "pop", -14.0, 1.0 + index * 0.06, 0.02)


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
	_action_button.text = L.t(target.get_prompt()) if _touch else "E — " + L.t(target.get_prompt())
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
	_completion_title.text = L.t(plot.completed_title)
	_completion_reward.text = L.t("Награда: +%d монет") % plot.reward_coins
	_kill_stamp_tweens()
	var stamps := _fill_stamps(_completion_stamps, plot)
	_completion.visible = true
	Juice.pop_in(_completion_panel, 0.4)
	Sfx.play("pop")
	var title_tween := create_tween()
	_stamp_tweens.append(title_tween)
	title_tween.tween_interval(0.2)
	title_tween.tween_callback(func() -> void:
		Juice.slam(_completion_title, 1.6, 0.2)
		Sfx.play("stamp", -2.0))
	# Штампы падают по одному, как печати.
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
			if shown_alpha > 0.9:
				Juice.slam(stamp, 1.7, 0.18)
				Sfx.play("stamp", -5.0, 0.95 + 0.05 * i, 0.0)
				Sfx.buzz(10)
			else:
				Juice.punch(stamp, 0.1))


# Камера едет к калитке участка, который только что открылся, калитка
# распахивается, и камера возвращается. Игрок в это время стоит.
func _reveal_next_plot() -> void:
	if _revealing:
		return
	_revealing = true
	for plot: Plot in get_tree().get_nodes_in_group("plot"):
		if not plot.reveal_pending:
			continue
		var camera := get_viewport().get_camera_3d() as FollowCamera
		if camera == null or plot.fence == null:
			plot.reveal()
			continue
		if _player:
			_player.controls_enabled = false
		camera.show_point(plot.fence.get_gate_position() + Vector3.UP * 0.8, plot.reveal)
		await camera.reveal_finished
		if _player and not _title_panel.visible:
			_player.controls_enabled = true
	_revealing = false


# Участок выкошен настолько, что открылся следующий: чуть погодя камера
# показывает его калитку.
func _on_next_opened() -> void:
	_update_goal_mark()
	Juice.punch(_plot_bar, 0.25, 0.4)
	Sfx.play("chime", -6.0)
	if not auto_reveal:
		return
	await get_tree().create_timer(REVEAL_DELAY).timeout
	_reveal_next_plot()


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
		_pause_title.text = L.t(_plot.plot_name)
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


# Включает выбранную сенсорную схему: один из видов джойстика или «вести пальцем».
func _apply_touch_controls() -> void:
	var scheme := GameState.touch_controls
	var stick := _controls_live and scheme != 2
	_joystick.visible = stick
	_joystick.process_mode = Node.PROCESS_MODE_PAUSABLE if stick else Node.PROCESS_MODE_DISABLED
	if scheme == 0:
		# Закреплённый джойстик: всегда виден, стоит слева внизу и никуда не
		# уезжает. Слушает касания только в своей части экрана.
		_joystick.joystick_mode = VirtualJoystick.JOYSTICK_FIXED
		# Без сенсорного экрана (компьютер) джойстик не показываем.
		_joystick.visibility_mode = VirtualJoystick.VISIBILITY_ALWAYS if _touch \
				else VirtualJoystick.VISIBILITY_WHEN_TOUCHED
		_joystick.anchor_left = 0.0
		_joystick.anchor_top = 0.3
		_joystick.anchor_right = 0.45
		_joystick.anchor_bottom = 1.0
		_joystick.initial_offset_ratio = FIXED_STICK_AT
	else:
		# Джойстик появляется под пальцем в любом месте экрана и идёт за ним.
		_joystick.joystick_mode = VirtualJoystick.JOYSTICK_FOLLOWING
		_joystick.visibility_mode = VirtualJoystick.VISIBILITY_WHEN_TOUCHED
		_joystick.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_joystick.set_offset(side, 0.0)
	_touch_pad.visible = _controls_live and scheme == 2
	if _player:
		_player.touch_pad = _touch_pad if scheme == 2 else null


# Следующий язык по кругу. Тексты уже построены, поэтому сцена
# перезагружается: игра сохранена, титульный экран второй раз не показывается.
func _switch_language() -> void:
	var codes: Array = GameState.LANGUAGES.keys()
	GameState.set_language(codes[(codes.find(GameState.get_language()) + 1) % codes.size()])
	get_tree().paused = false
	get_tree().reload_current_scene()


func _update_settings_buttons() -> void:
	# Кнопка языка подписана на обоих языках: её найдёт и тот, кто не читает текущий.
	var language_name: String = GameState.LANGUAGES[GameState.get_language()]
	_language_button.text = L.t("Язык: %s") % language_name
	_title_language_button.text = "Language / Язык: %s" % language_name
	_controls_button.text = L.t("Управление: %s") % L.t(GameState.TOUCH_CONTROLS[GameState.touch_controls])
	_sound_button.text = "Звуки: включены" if GameState.sound_enabled else "Звуки: выключены"
	_music_button.text = "Музыка: включена" if GameState.music_enabled else "Музыка: выключена"
	_graphics_button.text = L.t("Графика: %s") % L.t(Graphics.preset["title"])
	_fps_button.text = "Счётчик FPS: включён" if GameState.show_fps else "Счётчик FPS: выключен"
	_fps_label.visible = GameState.show_fps


# Замер кадра: игра снимается с паузы, слои картинки по очереди выключаются,
# таблица с ценой каждого показывается в меню паузы и копируется в буфер.
func _run_probe() -> void:
	if _probe:
		return
	_set_paused(false)
	if _player:
		_player.controls_enabled = false
	_probe = FrameProbe.new()
	add_child(_probe)
	_probe.finished.connect(func(text: String) -> void:
		_probe.queue_free()
		_probe = null
		_toast.visible = false
		if _player:
			_player.controls_enabled = true
		_set_paused(true)
		_show_probe_result(text))
	_probe.run()


# Окно с таблицей замера поверх меню паузы.
func _show_probe_result(text: String) -> void:
	var shade := ColorRect.new()
	shade.name = "ProbeResult"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 16)
	panel.add_child(rows)
	var label := Label.new()
	label.text = text + L.t("\n\nТаблица скопирована в буфер обмена — пришлите её.")
	label.add_theme_font_size_override("font_size", 26)
	rows.add_child(label)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(shade.queue_free)
	rows.add_child(close)


# Сведения об устройстве: помогают разобраться, если на телефоне что-то не так.
func _diagnostics() -> String:
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	return L.t("%d FPS · окно %d×%d · холст %d×%d · безопасная область %d,%d %d×%d · %s · %s · графика: %s") % [
		Engine.get_frames_per_second(), window.x, window.y, int(_root.size.x), int(_root.size.y),
		safe.position.x, safe.position.y, safe.size.x, safe.size.y,
		OS.get_model_name(), RenderingServer.get_video_adapter_name(), L.t(Graphics.preset["title"])]


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
	_workshop_coins.text = L.t("Найдено вещей: %d из %d · Монеты: %d") % [found, finds.size(), GameState.coins]
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
		var find_name := L.t(find.display_name)
		title.text = find_name.left(1).to_upper() + find_name.substr(1)
		text.add_child(title)
		var about := Label.new()
		about.add_theme_font_size_override("font_size", 28)
		about.modulate.a = 0.7
		about.text = L.t("Владелец: %s") % L.t(find.owner_name)
		text.add_child(about)
		if find.is_returned():
			var done := Label.new()
			done.text = "Возвращено"
			done.add_theme_color_override("font_color", GREEN_DARK)
			done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(done)
			continue
		var give := Button.new()
		give.text = L.t("Вернуть · +%d") % find.return_reward
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
		show_toast("%s: %s" % [L.t(find.owner_name), L.t(find.thanks)])
	_fill_bureau()
	Juice.punch(_workshop_coins, 0.2)


# Строки мастерской: по одной на апгрейд, с ценой следующего уровня.
func _fill_workshop() -> void:
	for child in _workshop_rows.get_children():
		child.queue_free()
	_workshop_title.text = "Мастерская"
	_workshop_coins.text = L.t("Монеты: %d") % GameState.coins
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
		title.text = L.t("%s — уровень %d из %d") % [L.t(info["title"]), level + 1, values.size()]
		text.add_child(title)
		var about := Label.new()
		about.add_theme_font_size_override("font_size", 28)
		about.modulate.a = 0.7
		if GameState.is_upgrade_maxed(id):
			about.text = "%s: %s %s" % [L.t(info["about"]), _number(values[level]), L.t(info["unit"])]
		else:
			about.text = "%s: %s → %s %s" % [L.t(info["about"]), _number(values[level]),
					_number(values[level + 1]), L.t(info["unit"])]
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
		buy.text = L.t("%d монет") % cost
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
