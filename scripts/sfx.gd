extends Node
## Звуки, музыка и вибрация. Автозагрузка «Sfx».
##
## Звуки лежат в assets/audio/<имя>.ogg или .wav. Если есть варианты
## <имя>_1, <имя>_2, …, каждый раз играет случайный. Удары, монеты, клики,
## калитка — из наборов Kenney (tools/import_sounds.py); мелодичные звуки и
## птицы синтезированы (tools/make_placeholder_sounds.py).
##
## Музыка — все .ogg из assets/music/, по кругу в случайном порядке,
## с плавными переходами. Авторы — в CREDITS.md.

const DIRECTORY := "res://assets/audio/"
const MUSIC_DIRECTORY := "res://assets/music/"
const EXTENSIONS := ["ogg", "wav"]
const VOICES := 10
## Громкость музыки: тише звуков, чтобы не мешала.
const MUSIC_VOLUME_DB := -9.0
const MUSIC_FADE := 2.5
## Пауза между треками, секунд.
const MUSIC_GAP := 4.0

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: AudioStreamPlayer
var _playlist: Array[String] = []
var _track := -1
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_bus("SFX")
	_create_bus("Music")
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.volume_db = -80.0
	_music.finished.connect(_on_track_finished)
	add_child(_music)
	_playlist = _list_music()
	_playlist.shuffle()
	GameState.settings_changed.connect(_apply_settings)
	_apply_settings()
	# Первый трек начинается не сразу: сначала слышно двор.
	get_tree().create_timer(1.5).timeout.connect(_next_track)


## Проигрывает короткий звук. pitch_variation слегка меняет высоту,
## чтобы повторы не звучали одинаково.
func play(sound: String, volume_db := 0.0, pitch := 1.0, pitch_variation := 0.05) -> void:
	var variants := _variants(sound)
	if variants.is_empty():
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = variants.pick_random()
	voice.volume_db = volume_db
	voice.pitch_scale = pitch * randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	voice.play()


## Короткая вибрация на телефоне.
func buzz(milliseconds := 20) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(milliseconds)


## Название играющего трека (для проверок и титров).
func current_track() -> String:
	return _playlist[_track].get_file().get_basename() if _track >= 0 else ""


func _variants(sound: String) -> Array:
	if _streams.has(sound):
		return _streams[sound]
	var found: Array = []
	var single := _load(sound)
	if single:
		found.append(single)
	var index := 1
	while true:
		var variant := _load("%s_%d" % [sound, index])
		if variant == null:
			break
		found.append(variant)
		index += 1
	_streams[sound] = found
	return found


func _load(file_name: String) -> AudioStream:
	for extension: String in EXTENSIONS:
		var path := DIRECTORY + file_name + "." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return null


func _list_music() -> Array[String]:
	var tracks: Array[String] = []
	# В экспортированной игре рядом лежат только .import; по ним и ищем.
	for file in ResourceLoader.list_directory(MUSIC_DIRECTORY):
		if file.get_extension() == "ogg":
			tracks.append(MUSIC_DIRECTORY + file)
	return tracks


func _next_track() -> void:
	if _playlist.is_empty():
		return
	_track = (_track + 1) % _playlist.size()
	var stream := load(_playlist[_track]) as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = false
	_music.stream = stream
	_music.volume_db = -40.0
	_music.play()
	_fade_music(MUSIC_VOLUME_DB)


func _on_track_finished() -> void:
	get_tree().create_timer(MUSIC_GAP).timeout.connect(_next_track)


func _fade_music(target_db: float) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", target_db, MUSIC_FADE)


func _create_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")


func _apply_settings() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not GameState.sound_enabled)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not GameState.music_enabled)
