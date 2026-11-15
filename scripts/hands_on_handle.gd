class_name HandsOnHandle
extends SkeletonModifier3D
## Руки героя лежат на ручке косилки, голова смотрит на то, что интересно.
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

## Насколько голова может повернуться (вбок) и наклониться (вверх-вниз), радианы.
const HEAD_YAW := 1.1
const HEAD_PITCH := 0.35

## Рукоятки (узлы на косилке); какая рука к какой — по стороне.
var grips: Array[Node3D] = []
## Куда смотрит голова (точка в мире) и насколько (0 — прямо, как в анимации).
var look_target := Vector3.ZERO
var look_weight := 0.0
## Насколько руки держат ручку (0 — руки свободны, как в анимации). Отдельно
## от influence модификатора: тот ослабил бы и поворот головы.
var hands_weight := 1.0
## Насколько ладони не дотянулись до рукояток в последний раз, метры
## (не ноль, только если руке не хватило растяжения), и сколько раз руки
## ставились: поза скелета после кадра возвращается к анимации, так что
## снаружи результат иначе не проверить.
var last_miss := 0.0
var updates := 0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	_look(skeleton, to_skeleton)
	if grips.is_empty() or hands_weight <= 0.0:
		return
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
		var aimed := Basis(along * stretch, up, across)
		if hands_weight < 1.0:
			# Переход (руки отпускают ручку и берутся снова) — доли секунды.
			aimed = Basis(pose.basis.x.lerp(aimed.x, hands_weight), pose.basis.y.lerp(aimed.y, hands_weight),
					pose.basis.z.lerp(aimed.z, hands_weight))
		skeleton.set_bone_global_pose(bone, Transform3D(aimed, pose.origin))


# Голова поворачивается к look_target: модель смотрит вдоль +Z скелета.
func _look(skeleton: Skeleton3D, to_skeleton: Transform3D) -> void:
	if look_weight <= 0.001:
		return
	var bone := skeleton.find_bone("head")
	if bone == -1:
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var to := to_skeleton * look_target - pose.origin
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.001:
		return
	var yaw := clampf(atan2(to.x, to.z), -HEAD_YAW, HEAD_YAW) * look_weight
	var pitch := clampf(atan2(to.y, flat), -HEAD_PITCH, HEAD_PITCH) * look_weight
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	skeleton.set_bone_global_pose(bone, Transform3D(turn * pose.basis, pose.origin))
