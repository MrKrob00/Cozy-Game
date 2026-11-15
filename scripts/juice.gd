class_name Juice
## Мелкие эффекты отклика: подпрыгивания интерфейса, всплывающий текст,
## искры, конфетти, листья, качание от удара, комочки травы в полёте.


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
static func dust(host: Node, at: Vector3, amount := 10) -> CPUParticles3D:
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
	return particles


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


## Листья слетают с кроны и, покачиваясь, опускаются на землю.
static func leaves(host: Node, at: Vector3, amount := 9, spread_radius := 1.4) -> void:
	var particles := _burst(host, at, amount, 2.2)
	particles.explosiveness = 0.55
	# Лист — своя модель (tools/make_models.py, fx_leaf): сложен по прожилке,
	# с черешком; свет дня как у всего остального. Оттенок у каждого свой.
	particles.mesh = Models.mesh("fx_leaf")
	particles.material_override = Placeholder.material(Color.WHITE)
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.8])
	colors.colors = PackedColorArray([Color(0.56, 0.80, 0.30).srgb_to_linear(),
			Color(0.72, 0.86, 0.34).srgb_to_linear(), Color(0.94, 0.80, 0.30).srgb_to_linear(),
			Color(0.95, 0.60, 0.26).srgb_to_linear()])
	particles.color_initial_ramp = colors
	# Крона большая (около 3 м): лист в полтора-два раза крупнее настоящего,
	# иначе сверху его не разглядеть.
	particles.scale_amount_min = 1.4
	particles.scale_amount_max = 1.9
	# С края кроны, кольцом: изнутри листьев не было бы видно.
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = spread_radius
	particles.emission_ring_inner_radius = spread_radius * 0.85
	particles.emission_ring_height = 1.2
	particles.spread = 180.0
	particles.initial_velocity_min = 0.2
	particles.initial_velocity_max = 0.7
	particles.gravity = Vector3(0.35, -1.3, 0.1)
	particles.damping_min = 0.8
	particles.damping_max = 1.6
	particles.angular_velocity_min = -280.0
	particles.angular_velocity_max = 280.0
	particles.emitting = true


## Облачко из мотора: косилка тронулась с места.
static func puff(host: Node, at: Vector3, amount := 5) -> void:
	var particles := dust(host, at, amount)
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.85), Color(1.0, 1.0, 1.0, 0.0)])
	particles.color_ramp = fade
	particles.direction = Vector3(0.0, 1.0, 0.4)
	particles.spread = 30.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.4
	particles.gravity = Vector3(0.0, 0.6, 0.0)


## Огонёк в траве: здесь что-то спрятано.
static func glint(host: Node, at: Vector3, color := Color(1.0, 0.93, 0.55)) -> void:
	var particles := _burst(host, at, 6, 0.8)
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 6
	mesh.rings = 3
	particles.mesh = mesh
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = color
	particles.material_override = glow
	var size := Curve.new()
	size.add_point(Vector2(0.0, 0.2))
	size.add_point(Vector2(0.3, 1.0))
	size.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = size
	particles.spread = 70.0
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 1.2
	particles.gravity = Vector3(0.0, 0.2, 0.0)
	particles.damping_min = 1.0
	particles.damping_max = 1.5
	particles.emitting = true


## Объект качается и затихает (дерево или скамейка от удара). push — куда
## толкнули, в мире; качание — вокруг основания узла.
static func wobble(node: Node3D, push: Vector3, amount := 0.07, duration := 1.1) -> void:
	_stop(node)
	var parent := node.get_parent() as Node3D
	var axis := Vector3.UP.cross(Vector3(push.x, 0.0, push.z))
	if axis.length_squared() < 0.0001:
		return
	if parent:
		axis = parent.global_basis.inverse() * axis
	axis = axis.normalized()
	var base := node.transform.basis
	var tween := node.create_tween()
	tween.tween_method(func(t: float) -> void:
		var angle := amount * sin(t * TAU * 2.5) * pow(1.0 - t, 2.0)
		node.transform.basis = Basis(axis, angle) * base, 0.0, 1.0, duration)
	node.set_meta("juice_tween", tween)


## Комочки летят дугой из from в to (трава из мешка в компостный ящик).
## Возвращает, сколько секунд до прилёта последнего.
static func toss(host: Node, from: Vector3, to: Vector3, count := 8, duration := 0.45,
		height := 1.1) -> float:
	# Комок спутанных травинок — своя модель (tools/make_models.py, fx_clump).
	var mesh := Models.mesh("fx_clump")
	var material := Placeholder.vertex_material()
	var stagger := 0.04
	for i in count:
		var clump := MeshInstance3D.new()
		clump.mesh = mesh
		clump.material_override = material
		clump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(clump)
		clump.global_position = from
		clump.scale = Vector3.ONE * 0.01
		var side := Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		var spin := Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		var lift := height * randf_range(0.85, 1.15)
		var size := randf_range(0.8, 1.25)
		var tween := clump.create_tween()
		tween.tween_interval(stagger * i)
		tween.tween_method(func(t: float) -> void:
			clump.global_position = from.lerp(to + side, t) + Vector3.UP * lift * 4.0 * t * (1.0 - t)
			clump.rotation = spin * t
			clump.scale = Vector3.ONE * size * minf(t * 5.0, 1.0) * lerpf(1.0, 0.6, t), 0.0, 1.0, duration)
		tween.tween_callback(clump.queue_free)
	return stagger * (count - 1) + duration


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
