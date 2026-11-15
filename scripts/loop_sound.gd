class_name LoopSound
extends AudioStreamPlayer
## Звук по кругу (дождь, жужжание пчёл): плавно появляется и гаснет.
## Громкость задаёт событие (например, по расстоянию до героя). Шина — SFX,
## так что выключенные звуки выключают и его.

const FADE := 1.2

var level_db := -12.0
var _fade := 0.0
var _fading_out := false


static func create(sound: String, volume_db: float) -> LoopSound:
	var player := LoopSound.new()
	player.bus = &"SFX"
	var path := "res://assets/audio/%s.ogg" % sound
	var stream := load(path) as AudioStreamOggVorbis
	if stream:
		stream = stream.duplicate()
		stream.loop = true
	player.stream = stream
	player.level_db = volume_db
	player.volume_db = -60.0
	return player


func _ready() -> void:
	if stream:
		play(randf() * 2.0)


func _process(delta: float) -> void:
	_fade = move_toward(_fade, 0.0 if _fading_out else 1.0, delta / FADE)
	volume_db = lerpf(-60.0, level_db, sqrt(_fade))
	if _fading_out and _fade <= 0.0:
		queue_free()


## Плавно стихает и удаляется.
func fade_out() -> void:
	_fading_out = true
