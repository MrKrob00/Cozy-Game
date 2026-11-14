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
// Земля ровная: свет без тени и доля, которую снимает тень, одинаковы для
// всех её точек и считаются на вершинах.
varying vec3 v_light;
varying vec3 v_drop;
varying float v_haze;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world.xz;
	v_light = day_light(vec3(0.0, 1.0, 0.0), 0.0);
	v_drop = day_shadow(vec3(0.0, 1.0, 0.0)) * shade_strength;
	v_haze = day_haze(distance(world, CAMERA_POSITION_WORLD));
}

void fragment() {
	vec2 uv = mow_uv(v_world_xz);
	vec3 mask = texture(mow_mask, uv).rgb;
	// Кайма вокруг поля (до забора) — такой же стриженый газон, как внутри.
	vec2 within = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	mask = mix(vec3(0.0, LAWN_TONE, 0.0), mask, within.x * within.y);
	float cut = 1.0 - smoothstep(0.0, 0.25, mask.r);
	vec3 surface = mix(cut_color(clamp(mask.g + lawn_mottle(v_world_xz), 0.0, 1.0)), bare_color, mask.b);
	vec3 color = mix(overgrown_color, surface, cut);
	vec3 lit = day_grade(color * (v_light - v_drop * shade_raw(v_world_xz)));
	ALBEDO = mix(lit, haze_color, v_haze);
}
