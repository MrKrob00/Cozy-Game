// Маска покоса. Общая часть для шейдеров травы и земли.
// R — высота травы (0 = скошено), G — тон полосы,
// B — «голая» ячейка: под травой не газон, а дорожка или земля.

uniform sampler2D mow_mask : filter_linear, repeat_disable;
// Центр поля и его оси в мировых координатах (поле может быть повёрнуто).
uniform vec2 field_center;
uniform vec2 field_x = vec2(1.0, 0.0);
uniform vec2 field_z = vec2(0.0, 1.0);
uniform vec2 field_size = vec2(1.0);

uniform vec3 cut_color_light : source_color = vec3(0.62, 0.85, 0.36);
uniform vec3 cut_color_dark : source_color = vec3(0.42, 0.70, 0.27);

vec2 mow_uv(vec2 world_xz) {
	vec2 offset = world_xz - field_center;
	return vec2(dot(offset, field_x), dot(offset, field_z)) / field_size + 0.5;
}

// Тон газона, по которому ещё не ездили (как TONE_NEUTRAL в маске).
const float LAWN_TONE = 0.502;

// Лёгкая неоднородность газона: мягкие пятна в мировых координатах, чтобы
// стриженая трава не была ровной заливкой. Без текстур.
float lawn_mottle(vec2 xz) {
	return 0.07 * sin(xz.x * 1.31 + xz.y * 0.73) * sin(xz.y * 1.17 - xz.x * 0.49)
			+ 0.03 * sin(xz.x * 3.7 - xz.y * 2.9);
}

vec3 cut_color(float tone) {
	return mix(cut_color_dark, cut_color_light, tone);
}
