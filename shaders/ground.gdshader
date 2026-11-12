// Земля под травой: на скошенных местах рисует газон с полосами.
shader_type spatial;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/mow_mask.gdshaderinc"

uniform vec3 overgrown_color : source_color = vec3(0.14, 0.38, 0.19);
uniform vec3 bare_color : source_color = vec3(0.66, 0.54, 0.38);

varying vec2 v_world_xz;

void vertex() {
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec3 mask = texture(mow_mask, mow_uv(v_world_xz)).rgb;
	float cut = 1.0 - smoothstep(0.0, 0.25, mask.r);
	vec3 surface = mix(cut_color(mask.g), bare_color, mask.b);
	ALBEDO = mix(overgrown_color, surface, cut);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR);
}
