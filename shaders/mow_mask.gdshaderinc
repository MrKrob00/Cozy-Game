// Маска покоса: R — высота травы (0 = скошено), G — тон полосы.
// Общая часть для шейдеров травы и земли.

uniform sampler2D mow_mask : filter_linear, repeat_disable;
uniform vec2 field_min;
uniform vec2 field_size = vec2(1.0);

uniform vec3 cut_color_light : source_color = vec3(0.62, 0.85, 0.36);
uniform vec3 cut_color_dark : source_color = vec3(0.42, 0.70, 0.27);

vec2 mow_uv(vec2 world_xz) {
	return (world_xz - field_min) / field_size;
}

vec3 cut_color(float tone) {
	return mix(cut_color_dark, cut_color_light, tone);
}
