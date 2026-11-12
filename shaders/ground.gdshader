// Земля под травой: на скошенных местах рисует газон с полосами.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/mow_mask.gdshaderinc"

uniform vec3 overgrown_color : source_color = vec3(0.14, 0.38, 0.19);

varying vec2 v_world_xz;

void vertex() {
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 mask = texture(mow_mask, mow_uv(v_world_xz)).rg;
	float cut = 1.0 - smoothstep(0.0, 0.25, mask.r);
	ALBEDO = mix(overgrown_color, cut_color(mask.g), cut);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR);
}
