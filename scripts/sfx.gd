extends Node
## Звуки и вибрация. Автозагрузка «Sfx».
##
## Звуки лежат в assets/audio/<имя>.wav. Сейчас это временные синтезированные
## звуки (см. tools/make_placeholder_sounds.py); чтобы заменить звук,
## достаточно положить свой файл с тем же именем.

const DIRECTORY := "res://assets/audio/"
const VOICES := 10

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	GameState.settings_changed.connect(_apply_settings)
	_apply_settings()


## Проигрывает короткий звук. pitch_variation слегка меняет высоту,
## чтобы повторы не звучали одинаково.
func play(sound: String, volume_db := 0.0, pitch := 1.0, pitch_variation := 0.05) -> void:
	var audio := _stream(sound)
	if audio == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = audio
	voice.volume_db = volume_db
	voice.pitch_scale = pitch * randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	voice.play()


## Создаёт проигрыватель для зацикленного звука (мотор, шелест травы).
## Громкостью и высотой управляет владелец.
func create_loop(sound: String, parent: Node) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = _stream(sound)
	player.volume_db = -80.0
	parent.add_child(player)
	if player.stream:
		player.play()
	return player


## Короткая вибрация на телефоне.
func buzz(milliseconds := 20) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(milliseconds)


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := DIRECTORY + sound + ".wav"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


func _apply_settings() -> void:
	AudioServer.set_bus_mute(0, not GameState.sound_enabled)
