// Стрелки-указатели на земле: бегущий огонёк идёт вдоль дорожки к цели.
// Без текстур и без теста глубины не обходится: стрелки лежат на земле.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.70, 0.16);
uniform float speed = 1.1;

varying float v_phase;
varying float v_fade;

void vertex() {
	// R — место стрелки вдоль дорожки, G — насколько она видна (первые гаснут).
	v_phase = INSTANCE_CUSTOM.r;
	v_fade = INSTANCE_CUSTOM.g;
}

void fragment() {
	float wave = fract(v_phase - TIME * speed);
	float glow = smoothstep(0.6, 1.0, wave);
	ALBEDO = mix(tint, vec3(1.0, 0.98, 0.80), glow * 0.75);
	ALPHA = (0.68 + 0.32 * glow) * v_fade;
}
