class_name HandsOnHandle
extends SkeletonModifier3D
## Руки героя лежат на ручке косилки.
##
## У модели Kenney рука — одна кость, поэтому хватает прицела: после анимации
## каждая рука поворачивается от плеча к своей рукоятке и чуть тянется по
## длине, чтобы ладонь попала точно на неё. Косилка дрожит, герой шагает и
## наклоняется — кисти остаются на ручке.

## От плеча до середины ладони в позе покоя, в единицах модели.
const REACH := 0.25
## Насколько рука может укоротиться или вытянуться.
const STRETCH_MIN := 0.75
const STRETCH_MAX := 1.3
const ARMS: Array[String] = ["arm-left", "arm-right"]

## Рукоятки (узлы на косилке); какая рука к какой — по стороне.
var grips: Array[Node3D] = []
## Насколько ладони не дотянулись до рукояток в последний раз, метры
## (не ноль, только если руке не хватило растяжения), и сколько раз руки
## ставились: поза скелета после кадра возвращается к анимации, так что
## снаружи результат иначе не проверить.
var last_miss := 0.0
var updates := 0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or grips.is_empty():
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var meters := skeleton.global_basis.get_scale().x
	last_miss = 0.0
	updates += 1
	for arm in ARMS:
		var bone := skeleton.find_bone(arm)
		if bone == -1:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		# В позе покоя левая рука смотрит вдоль +X, правая — вдоль −X.
		var side := signf(skeleton.get_bone_global_rest(bone).origin.x)
		var target := Vector3.ZERO
		var found := false
		for grip in grips:
			if not is_instance_valid(grip):
				continue
			var at := to_skeleton * grip.global_position
			if signf(at.x) == side:
				target = at
				found = true
		if not found:
			continue
		var reach := target - pose.origin
		var length := reach.length()
		if length < 0.001:
			continue
		var along := reach / length * side
		var across := along.cross(Vector3.UP)
		if across.length_squared() < 0.0001:
			continue
		across = across.normalized()
		var up := across.cross(along)
		var stretch := clampf(length / REACH, STRETCH_MIN, STRETCH_MAX)
		last_miss = maxf(last_miss, absf(length - REACH * stretch) * meters)
		skeleton.set_bone_global_pose(bone, Transform3D(Basis(along * stretch, up, across), pose.origin))
