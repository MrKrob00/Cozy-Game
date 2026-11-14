class_name FrameProbe
extends Node
## Замер кадра на самом устройстве, слой за слоем (кнопка в меню паузы).
##
## Телефон в Compatibility не даёт времени видеокарты, а компьютер о цене
## пикселя на телефоне ничего не говорит, поэтому устройство меряет себя само:
## каждый слой картинки выключается на пару секунд между двумя замерами
## с включённым, и цена слоя — разница среднего времени кадра. На время замера
## выключена привязка к частоте экрана. Таблица показывается в меню паузы
## и копируется в буфер обмена. Приём взят из Voxel-RTS (frame_probe.gd).

signal finished(text: String)

## Секунд ждать после переключения и секунд считать кадры.
var settle := 0.5
var window := 1.6

var status := ""

var _lines: Array[String] = []


func run() -> void:
	_lines.clear()
	var vsync := DisplayServer.window_get_vsync_mode()
	var max_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var view := get_tree().root
	_lines.append(L.t("ЗАМЕР  %s  %s") % [OS.get_model_name(), RenderingServer.get_video_adapter_name()])
	_lines.append(L.t("экран %d×%d, 3D ×%.2f, графика: %s") % [view.size.x, view.size.y, view.scaling_3d_scale,
			L.t(Graphics.preset["title"])])
	var base: float = await _measure()
	_lines.append(L.t("вызовов отрисовки %d, треугольников %d") % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	_lines.append(L.t("кадр %.1f мс (%d к/с)%s") % [base, int(1000.0 / maxf(base, 0.1)),
			L.t("  (возможно, упёрлись в частоту экрана)") if base < 16.9 else ""])
	_lines.append(L.t("сколько стоит слой (кадр без него дешевле на столько):"))
	for case: Array in _cases():
		status = L.t("Замер: %s…") % L.t(case[0])
		var toggle: Callable = case[1]
		toggle.call(false)
		var off: float = await _measure()
		toggle.call(true)
		var on: float = await _measure()
		_lines.append(L.t("%-22s %+5.1f мс") % [L.t(case[0]), (base + on) * 0.5 - off])
		base = on
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	status = ""
	var text := "\n".join(_lines)
	DisplayServer.clipboard_set(text)
	finished.emit(text)


# Слои: название и переключатель (true — включить).
func _cases() -> Array:
	var tree := get_tree()
	var view := tree.root
	var fields := tree.get_nodes_in_group("mow_field")
	var decor := tree.current_scene.get_node_or_null("Decor") if tree.current_scene else null
	var shadows := tree.current_scene.get_node_or_null("Shadows") as Shadows if tree.current_scene else null
	var player := tree.get_first_node_in_group("player") as Node3D
	var hud := tree.get_first_node_in_group("hud") as CanvasLayer
	var msaa := view.msaa_3d
	var scale := view.scaling_3d_scale
	var cases := [
		["трава", func(on: bool) -> void:
			for field: MowField in fields:
				field.set_layer_visible("grass", on)],
		["земля участков", func(on: bool) -> void:
			for field: MowField in fields:
				field.set_layer_visible("ground", on)],
		["луг и дороги", func(on: bool) -> void: _show_decor(decor, on, true, false)],
		["дома и деревья", func(on: bool) -> void: _show_decor(decor, on, false, false)],
		["россыпи луга", func(on: bool) -> void: _show_decor(decor, on, false, true)],
		["герой и косилка", func(on: bool) -> void:
			if player:
				for child in player.get_children():
					if child is Node3D and not child is CollisionShape3D:
						child.visible = on],
		["интерфейс", func(on: bool) -> void:
			if hud:
				hud.visible = on],
		["сглаживание", func(on: bool) -> void:
			view.msaa_3d = msaa if on else Viewport.MSAA_DISABLED],
		["3D в полном размере", func(on: bool) -> void:
			view.scaling_3d_scale = scale if on else scale * 0.75],
	]
	if shadows:
		cases.insert(5, ["тени предметов", func(on: bool) -> void: shadows.set_enabled(on)])
	return cases


# Окружение деревни: земля с дорогами, объёмные модели или россыпи.
func _show_decor(decor: Node, on: bool, ground: bool, scatter: bool) -> void:
	if decor == null:
		return
	for node in decor.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.name == &"ShadowProxy":
			continue
		var in_scatter := false
		var parent := instance.get_parent()
		while parent and parent != decor:
			in_scatter = in_scatter or parent.name == &"Scatter"
			parent = parent.get_parent()
		var is_ground: bool = instance.get_meta("receives", false) and not in_scatter
		if in_scatter == scatter and (scatter or is_ground == ground):
			instance.visible = on


# Среднее время кадра за окно замера, мс.
func _measure() -> float:
	await get_tree().create_timer(settle, true, false, true).timeout
	var frames := 0
	var start := Time.get_ticks_usec()
	var end := start + int(window * 1000000.0)
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame
		frames += 1
	return float(Time.get_ticks_usec() - start) / 1000.0 / maxf(frames, 1.0)
