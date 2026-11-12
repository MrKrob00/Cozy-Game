// Общее мультяшное освещение: два тона (свет / тень) с мягкой границей.

vec3 toon_diffuse(vec3 normal, vec3 light_dir, float attenuation, vec3 light_color) {
	float facing = smoothstep(-0.02, 0.06, dot(normal, light_dir));
	float shadow = smoothstep(0.4, 0.55, attenuation);
	return light_color * (facing * shadow) / PI;
}
