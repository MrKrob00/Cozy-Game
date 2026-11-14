// Кромка газона за забором участка: тот же стриженый газон, что и у земли
// поля, плавно растворяется в луге (прозрачность — в альфе цвета вершин).
// Узкая полоса, рисуется после непрозрачного.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://shaders/day.gdshaderinc"
#include "res://shaders/shade.gdshaderinc"
#include "res://shaders/mow_mask.gdshaderinc"

varying vec2 v_world_xz;
varying vec3 v_light;
varying vec3 v_drop;
varying float v_haze;
varying float v_alpha;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world.xz;
	v_light = day_light(vec3(0.0, 1.0, 0.0), 0.0);
	v_drop = day_shadow(vec3(0.0, 1.0, 0.0)) * shade_strength;
	v_haze = day_haze(distance(world, CAMERA_POSITION_WORLD));
	v_alpha = COLOR.a;
}

void fragment() {
	vec3 color = cut_color(LAWN_TONE + lawn_mottle(v_world_xz));
	vec3 lit = day_grade(color * (v_light - v_drop * shade_raw(v_world_xz)));
	ALBEDO = mix(lit, haze_color, v_haze);
	ALPHA = v_alpha * v_alpha * (3.0 - 2.0 * v_alpha);
}
