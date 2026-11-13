// Тень предмета для картинки теней (scripts/shadows.gd): каждая вершина
// сдвигается вдоль солнечного луча на землю (y = 0), камера смотрит сверху.
// Свет — один параметр: поворот солнца ничего не перестраивает.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, world_vertex_coords;

uniform vec3 day_dir = vec3(0.353, -0.788, -0.504);

void vertex() {
	// Земля под предметом — высота его узла (участки стоят на террасах).
	float ground = MODEL_MATRIX[3].y;
	float lift = max(VERTEX.y - ground, 0.0) / max(-day_dir.y, 0.1);
	VERTEX.xz += day_dir.xz * lift;
	VERTEX.y = ground;
}

void fragment() {
	ALBEDO = vec3(1.0);
}
