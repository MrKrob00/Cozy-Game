// Тень предмета для картинки теней (scripts/shadows.gd): каждая вершина
// сдвигается вдоль солнечного луча на землю (y = 0), камера смотрит сверху.
// Свет — один параметр: поворот солнца ничего не перестраивает.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, world_vertex_coords;

uniform vec3 day_dir = vec3(-0.28, -0.76, -0.58);

void vertex() {
	// Земля под предметом — низ его детали (Placeholder пишет его в UV.y,
	// в координатах модели): участки и подъёмы на разной высоте.
	float ground = (MODEL_MATRIX * vec4(0.0, UV.y, 0.0, 1.0)).y;
	float lift = max(VERTEX.y - ground, 0.0) / max(-day_dir.y, 0.1);
	VERTEX.xz += day_dir.xz * lift;
	VERTEX.y = ground;
}

void fragment() {
	ALBEDO = vec3(1.0);
}
