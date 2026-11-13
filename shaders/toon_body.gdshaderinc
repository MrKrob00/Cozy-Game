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
// Ветер для склеенных моделей: сила — в альфе цвета вершины (листва, кочки).
uniform float sway_strength = 0.0;

varying vec3 v_normal;
#ifdef RECEIVE_SHADE
varying vec3 v_world;
#else
// Низ предмета темнее (как градиент палитры у Alba): мягкая тень у земли.
varying float v_ground_shade;
varying float v_haze;
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
	if (sway_strength > 0.0 && COLOR.a > 0.0) {
		vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float reach = COLOR.a * sway_strength * 0.12 * clamp(at.y, 0.0, 1.2);
		float gust = sin(TIME * 1.4 + at.x * 0.35 + at.z * 0.25) + 0.4 * sin(TIME * 2.3 + at.x * 0.9);
		VERTEX.x += reach * gust;
		VERTEX.z += reach * 0.6 * cos(TIME * 1.1 + at.z * 0.4);
	}
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef RECEIVE_SHADE
	v_world = world;
#else
	// Траву и цветы (у них есть качание) не затемняем: они сами у земли.
	v_ground_shade = COLOR.a > 0.0 ? 1.0 : mix(0.74, 1.0, smoothstep(0.0, 0.7, world.y));
	v_haze = day_haze(distance(world, CAMERA_POSITION_WORLD));
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
#ifdef RECEIVE_SHADE
	// Плоские поверхности большие и с редкими вершинами: дымка — на пиксель.
	vec3 color = day_grade(albedo * COLOR.rgb * day_light(normalize(v_normal), shade_at(v_world.xz)));
	ALBEDO = mix(color, haze_color, day_haze(distance(v_world, CAMERA_POSITION_WORLD)));
#else
	vec3 color = day_grade(albedo * COLOR.rgb * v_ground_shade * day_light(normalize(v_normal), 0.0));
	ALBEDO = mix(color, haze_color, v_haze);
#endif
}
