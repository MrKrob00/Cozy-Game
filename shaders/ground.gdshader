// Земля под травой: на скошенных местах рисует газон с полосами.
// Два чтения текстуры на пиксель (маска покоса и тени предметов) прямо по
// координатам с вершин. Всё, что не меняется от пикселя к пикселю, — на
// вершинах: свет, дымка, пятна газона (сетка через 0,5 м, см. MowField) и
// насыщенность цветов (flat: один раз на треугольник, без интерполяции).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://shaders/day.gdshaderinc"
#include "res://shaders/shade.gdshaderinc"
#include "res://shaders/mow_mask.gdshaderinc"

uniform vec3 overgrown_color : source_color = vec3(0.14, 0.38, 0.19);
uniform vec3 bare_color : source_color = vec3(0.66, 0.54, 0.38);
// Мокрый газон после дождика темнее (0 — сухой).
uniform float wetness = 0.0;

varying vec2 v_mask_uv;
varying vec3 v_shade;
varying float v_haze;
varying float v_mottle;
// Земля ровная: свет без тени и доля, которую снимает тень, одинаковы для
// всех её точек. Насыщенность (day_grade) берётся от цветов: свет почти
// белый, так что grade(цвет × свет) ≈ grade(цвет) × свет.
varying flat vec3 v_light;
varying flat vec3 v_drop;
varying flat vec3 v_overgrown;
varying flat vec3 v_bare;
varying flat vec3 v_cut_dark;
varying flat vec3 v_cut_light;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_mask_uv = mow_uv(world.xz);
	v_shade = shade_coords(world.xz);
	v_haze = day_haze(distance(world, CAMERA_POSITION_WORLD));
	v_mottle = lawn_mottle(world.xz);
	float dry = 1.0 - 0.16 * wetness;
	v_light = day_light(vec3(0.0, 1.0, 0.0), 0.0) * dry;
	v_drop = day_shadow(vec3(0.0, 1.0, 0.0)) * shade_strength * dry;
	v_overgrown = day_grade(overgrown_color);
	v_bare = day_grade(bare_color);
	v_cut_dark = day_grade(cut_color_dark);
	v_cut_light = day_grade(cut_color_light);
}

void fragment() {
	vec3 mask = texture(mow_mask, v_mask_uv).rgb;
	// Кайма вокруг поля (до забора) — такой же стриженый газон, как внутри.
	vec2 within = step(vec2(0.0), v_mask_uv) * step(v_mask_uv, vec2(1.0));
	mask = mix(vec3(0.0, LAWN_TONE, 0.0), mask, within.x * within.y);
	float cut = 1.0 - smoothstep(0.0, 0.25, mask.r);
	vec3 lawn = mix(v_cut_dark, v_cut_light, clamp(mask.g + v_mottle, 0.0, 1.0));
	vec3 color = mix(v_overgrown, mix(lawn, v_bare, mask.b), cut);
	vec3 lit = color * (v_light - v_drop * shade_lookup(v_shade));
	ALBEDO = mix(lit, haze_color, v_haze);
}
