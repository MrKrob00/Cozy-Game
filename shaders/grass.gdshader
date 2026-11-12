// Трава: высота пучка берётся из маски покоса, плюс ветер
// и раздвигание вокруг косилки.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

#include "res://shaders/toon.gdshaderinc"
#include "res://shaders/mow_mask.gdshaderinc"

uniform vec3 color_root : source_color = vec3(0.16, 0.45, 0.22);
uniform vec3 color_tip : source_color = vec3(0.55, 0.82, 0.30);
uniform vec3 color_tall_tip : source_color = vec3(0.80, 0.86, 0.38);
// Высота стерни относительно полной высоты пучка.
uniform float stubble = 0.1;
uniform float wind_strength = 0.07;
uniform float wind_speed = 1.6;
uniform vec3 pusher_position;
uniform float pusher_radius = 1.5;

varying float v_height;
varying float v_grown;
varying float v_tone;
varying float v_tall;
varying float v_random;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 mask = textureLod(mow_mask, mow_uv(root.xz), 0.0).rgb;
	float grown = smoothstep(0.0, 0.25, mask.r);
	// На «голых» ячейках (дорожки) после покоса стерни не остаётся.
	float scale = mix(stubble * (1.0 - mask.b), 1.0, mask.r);
	float along = UV.y;

	vec3 v = VERTEX;
	v.y = root.y + (v.y - root.y) * scale;

	// Ветер: качается только нескошенная трава, сильнее у кончика.
	float phase = TIME * wind_speed + root.x * 0.7 + root.z * 0.9;
	vec2 sway = vec2(sin(phase), cos(phase * 0.8 + 1.3));
	v.xz += sway * wind_strength * along * along * scale * grown;

	// Косилка и персонаж приминают и раздвигают траву вокруг себя.
	vec2 away = root.xz - pusher_position.xz;
	float push = (1.0 - smoothstep(pusher_radius * 0.35, pusher_radius, length(away))) * grown;
	v.y = root.y + (v.y - root.y) * (1.0 - 0.55 * push);
	v.xz += normalize(away + vec2(0.0001)) * push * along * 0.3;

	VERTEX = v;
	NORMAL = vec3(0.0, 1.0, 0.0);

	v_height = along;
	v_grown = grown;
	v_tone = mask.g;
	v_tall = smoothstep(0.7, 0.9, mask.r);
	v_random = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 tip = mix(color_tip, color_tall_tip, v_tall);
	vec3 tall = mix(color_root, tip, v_height) * (0.88 + 0.24 * v_random);
	vec3 cut = cut_color(v_tone) * (0.96 + 0.08 * v_random);
	ALBEDO = mix(cut, tall, v_grown);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_diffuse(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR);
}
