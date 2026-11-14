// Общая часть шейдеров тени (shadow_cast, shadow_cast_flat).
uniform vec3 day_dir = vec3(-0.28, -0.76, -0.58);

void vertex() {
	// Земля под предметом — низ его детали (Placeholder пишет его в UV.y,
	// в координатах модели): участки и подъёмы на разной высоте.
#ifdef FLAT_BASE
	// Готовые модели (персонажи): в UV у них текстура, земля — низ модели.
	float ground = MODEL_MATRIX[3].y;
#else
	float ground = (MODEL_MATRIX * vec4(0.0, UV.y, 0.0, 1.0)).y;
#endif
	float lift = max(VERTEX.y - ground, 0.0) / max(-day_dir.y, 0.1);
	VERTEX.xz += day_dir.xz * lift;
	VERTEX.y = ground;
}

void fragment() {
	ALBEDO = vec3(1.0);
}
