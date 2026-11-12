// Мультяшный материал для моделей: один цвет, двухтоновый свет.
// Параметр fade растворяет модель точками (кроны, заслоняющие игрока).
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;

const mat4 DITHER = mat4(
	vec4(0.03125, 0.53125, 0.15625, 0.65625),
	vec4(0.78125, 0.28125, 0.90625, 0.40625),
	vec4(0.21875, 0.71875, 0.09375, 0.59375),
	vec4(0.96875, 0.46875, 0.84375, 0.34375));

void fragment() {
	if (fade < 0.999) {
		ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
		if (fade < DITHER[cell.x][cell.y]) {
			discard;
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR);
}
