class_name Juice
## Мелкие эффекты отклика: подпрыгивания интерфейса, всплывающий текст,
## искры, конфетти.


## Элемент интерфейса на миг увеличивается и пружинит обратно.
static func punch(control: Control, amount := 0.2, duration := 0.3) -> void:
	_stop(control)
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * (1.0 + amount)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.set_meta("juice_tween", tween)


## Элемент интерфейса появляется: вырастает с лёгким перелётом.
static func pop_in(control: Control, duration := 0.28) -> void:
	_stop(control)
	control.visible = true
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * 0.7
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, duration) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, duration * 0.6)
	control.set_meta("juice_tween", tween)


## Объект сплющивается и пружинит обратно к масштабу base.
static func squash(node: Node3D, amount := 0.25, duration := 0.45, base := Vector3.ONE) -> void:
	_stop(node)
	node.scale = base * Vector3(1.0 + amount * 0.6, 1.0 - amount, 1.0 + amount * 0.6)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", base, duration) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	node.set_meta("juice_tween", tween)


## Элемент интерфейса «шлёпается» сверху, как печать: из крупного в обычный.
static func slam(control: Control, from_scale := 1.8, duration := 0.22) -> void:
	_stop(control)
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * from_scale
	var target_alpha := control.modulate.a
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "modulate:a", target_alpha, duration * 0.6)
	tween.set_parallel(false)
	tween.tween_property(control, "scale", Vector2.ONE * 1.06, 0.06)
	tween.tween_property(control, "scale", Vector2.ONE, 0.1)
	control.set_meta("juice_tween", tween)


## Облачко пыли у земли (косилка во что-то упёрлась).
static func dust(host: Node, at: Vector3, amount := 10) -> void:
	var particles := _burst(host, at, amount, 0.6)
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 6
	mesh.rings = 3
	particles.mesh = mesh
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.vertex_color_use_as_albedo = true
	particles.material_override = puff
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.92, 0.86, 0.72, 0.8), Color(0.92, 0.86, 0.72, 0.0)])
	particles.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.6))
	particles.scale_amount_curve = grow
	particles.spread = 80.0
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 1.4
	particles.gravity = Vector3(0.0, 0.4, 0.0)
	particles.damping_min = 1.5
	particles.damping_max = 2.5
	particles.emitting = true


## Текст всплывает над точкой в мире и растворяется.
static func floating_text(host: Node, at: Vector3, text: String, color := Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.pixel_size = 0.007
	label.outline_size = 20
	label.modulate = color
	label.outline_modulate = Color(0.2, 0.16, 0.12)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	host.add_child(label)
	label.global_position = at
	label.scale = Vector3.ONE * 0.4
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "global_position:y", at.y + 1.2, 1.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35)
	tween.parallel().tween_property(label, "outline_modulate:a", 0.0, 0.35)
	tween.tween_callback(label.queue_free)


## Короткая вспышка светящихся искр.
static func sparkle(host: Node, at: Vector3, color := Color(1.0, 0.95, 0.6), amount := 18) -> void:
	var particles := _burst(host, at, amount, 0.8)
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	mesh.radial_segments = 6
	mesh.rings = 3
	particles.mesh = mesh
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	particles.material_override = glow
	particles.spread = 75.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0.0, -3.0, 0.0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.4
	particles.emitting = true


## Кузнечики выпрыгивают из высокой травы, когда по ней идёт косилка.
static func critters(host: Node, at: Vector3, amount := 4) -> void:
	var particles := _burst(host, at, amount, 0.75)
	particles.mesh = Placeholder.box(Vector3(0.08, 0.06, 0.15))
	var body := StandardMaterial3D.new()
	body.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.albedo_color = Color(0.56, 0.78, 0.25)
	particles.material_override = body
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 2.6
	particles.initial_velocity_max = 4.0
	particles.gravity = Vector3(0.0, -9.0, 0.0)
	particles.angular_velocity_min = -400.0
	particles.angular_velocity_max = 400.0
	particles.emitting = true


## Пух летит из срезанного бурьяна и медленно уплывает по ветру.
static func fluff(host: Node, at: Vector3, amount := 9) -> void:
	var particles := _burst(host, at, amount, 2.4)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 5
	mesh.rings = 2
	particles.mesh = mesh
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.vertex_color_use_as_albedo = true
	particles.material_override = puff
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 1.0, 0.95, 0.95), Color(1.0, 1.0, 0.95, 0.8), Color(1.0, 1.0, 0.95, 0.0)])
	particles.color_ramp = fade
	particles.direction = Vector3(0.6, 1.0, -0.2)
	particles.spread = 40.0
	particles.initial_velocity_min = 0.9
	particles.initial_velocity_max = 2.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.3
	particles.gravity = Vector3(0.5, 0.25, -0.2)
	particles.damping_min = 0.6
	particles.damping_max = 1.2
	particles.emitting = true


## Разноцветное конфетти.
static func confetti(host: Node, at: Vector3, amount := 70) -> void:
	var particles := _burst(host, at, amount, 2.2)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.02, 0.16)
	particles.mesh = mesh
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.vertex_color_use_as_albedo = true
	particles.material_override = paper
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	colors.colors = PackedColorArray([
		Color(1.0, 0.45, 0.45), Color(1.0, 0.82, 0.3), Color(0.45, 0.8, 1.0),
		Color(0.7, 0.55, 1.0), Color(1.0, 1.0, 1.0),
	])
	particles.color_initial_ramp = colors
	particles.spread = 50.0
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 8.0
	particles.angular_velocity_min = -540.0
	particles.angular_velocity_max = 540.0
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.damping_min = 0.6
	particles.damping_max = 1.4
	particles.emitting = true


static func _burst(host: Node, at: Vector3, amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(particles)
	particles.global_position = at
	particles.finished.connect(particles.queue_free)
	return particles


static func _stop(node: Node) -> void:
	if not node.has_meta("juice_tween"):
		return
	var tween: Variant = node.get_meta("juice_tween")
	if tween is Tween and tween.is_valid():
		tween.kill()
