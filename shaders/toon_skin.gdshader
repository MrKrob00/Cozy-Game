// Готовые модели с текстурой-палитрой и скелетом (персонажи, зверьки):
// цвет из текстуры, свет дня — на вершинах, одно чтение текстуры на пиксель.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/day.gdshaderinc"

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear;
uniform vec3 albedo : source_color = vec3(1.0);

varying vec3 v_light;
varying float v_haze;

void vertex() {
	vec3 normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_light = day_light(normal, 0.0);
	v_haze = day_haze(distance(world, CAMERA_POSITION_WORLD));
}

void fragment() {
	vec3 color = day_grade(albedo * texture(albedo_tex, UV).rgb * v_light);
	ALBEDO = mix(color, haze_color, v_haze);
}
