// Кромка газона за забором участка: тот же стриженый газон, что и у земли
// поля, плавно растворяется в луге (прозрачность — в альфе цвета вершин).
// Узкая полоса, рисуется после непрозрачного. Цвет на солнце и в тени
// считается на вершинах; пикселю — одно чтение картинки теней и смешивание.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://shaders/day.gdshaderinc"
#include "res://shaders/shade.gdshaderinc"
#include "res://shaders/mow_mask.gdshaderinc"

varying vec3 v_sun;
varying vec3 v_dark;
varying vec3 v_shade;
varying float v_alpha;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 color = cut_color(LAWN_TONE + lawn_mottle(world.xz));
	vec3 light = day_light(vec3(0.0, 1.0, 0.0), 0.0);
	vec3 drop = day_shadow(vec3(0.0, 1.0, 0.0)) * shade_strength;
	float haze = day_haze(distance(world, CAMERA_POSITION_WORLD));
	v_sun = mix(day_grade(color * light), haze_color, haze);
	v_dark = mix(day_grade(color * (light - drop)), haze_color, haze);
	v_shade = shade_coords(world.xz);
	v_alpha = COLOR.a * COLOR.a * (3.0 - 2.0 * COLOR.a);
}

void fragment() {
	ALBEDO = mix(v_sun, v_dark, shade_lookup(v_shade));
	ALPHA = v_alpha;
}
