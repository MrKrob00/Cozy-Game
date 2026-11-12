// Мультяшный материал для моделей: один цвет, двухтоновый свет.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"

uniform vec3 albedo : source_color = vec3(1.0);

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR);
}
