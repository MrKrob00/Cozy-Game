// Земля под травой: на скошенных местах рисует газон с полосами.
// Два чтения текстуры на пиксель: маска покоса и тени предметов.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/day.gdshaderinc"
#include "res://shaders/shade.gdshaderinc"
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
	vec3 color = mix(overgrown_color, surface, cut);
	vec3 lit = day_grade(color * day_light(vec3(0.0, 1.0, 0.0), shade_at(v_world_xz)));
	ALBEDO = mix(lit, haze_color, day_haze(distance(vec3(v_world_xz.x, 0.0, v_world_xz.y), CAMERA_POSITION_WORLD)));
}
