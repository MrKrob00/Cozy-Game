// Мультяшный материал моделей: цвет (параметр × цвет вершины), свет дня.
// Варианты задаются #define перед подключением:
//   RECEIVE_SHADE — поверхность принимает тени предметов (земля, дорога);
//   FADE          — растворение точками (крона, заслонившая игрока; с discard,
//                   поэтому только на время растворения);
//   PLANT         — цветы: качаются на ветру и приминаются косилкой.
// Цвет вершин приходит в линейном пространстве (Placeholder.bake).

#include "res://shaders/day.gdshaderinc"
#ifdef RECEIVE_SHADE
#include "res://shaders/shade.gdshaderinc"
#endif

uniform vec3 albedo : source_color = vec3(1.0);
#ifdef FADE
uniform float fade : hint_range(0.0, 1.0) = 1.0;
#endif
#ifdef PLANT
uniform vec3 pusher_position = vec3(0.0, -100.0, 0.0);
uniform float pusher_radius = 0.8;
#endif

varying vec3 v_normal;
#ifdef RECEIVE_SHADE
varying vec2 v_world_xz;
#endif

void vertex() {
#ifdef PLANT
	// UV2 — основание стебля в координатах клумбы.
	vec2 base = UV2;
	float height = max(VERTEX.y, 0.0);
	float phase = TIME * 1.6 + base.x * 3.1 + base.y * 4.7;
	VERTEX.xz += vec2(sin(phase), cos(phase * 0.8)) * 0.12 * height;
	vec3 base_world = (MODEL_MATRIX * vec4(base.x, 0.0, base.y, 1.0)).xyz;
	float press = 1.0 - smoothstep(pusher_radius * 0.4, pusher_radius, distance(base_world.xz, pusher_position.xz));
	VERTEX.y *= 1.0 - 0.65 * press;
#endif
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
#ifdef RECEIVE_SHADE
	v_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
#endif
}

#ifdef FADE
const mat4 DITHER = mat4(
	vec4(0.03125, 0.53125, 0.15625, 0.65625),
	vec4(0.78125, 0.28125, 0.90625, 0.40625),
	vec4(0.21875, 0.71875, 0.09375, 0.59375),
	vec4(0.96875, 0.46875, 0.84375, 0.34375));
#endif

void fragment() {
#ifdef FADE
	ivec2 cell = ivec2(mod(FRAGCOORD.xy, 4.0));
	if (fade < DITHER[cell.x][cell.y]) {
		discard;
	}
#endif
	float shade = 0.0;
#ifdef RECEIVE_SHADE
	shade = shade_at(v_world_xz);
#endif
	ALBEDO = day_grade(albedo * COLOR.rgb * day_light(normalize(v_normal), shade));
}
