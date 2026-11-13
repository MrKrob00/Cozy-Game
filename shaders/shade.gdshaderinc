// Тени предметов на земле и траве: картинка сверху (scripts/shadows.gd),
// окно вокруг игрока. Одно чтение текстуры; за пределами окна теней нет.

uniform sampler2D shade_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec4 shade_rect = vec4(0.0);   // x, z угла окна; 1 / его размер (0 — выключено); доля мягкого края
uniform float shade_strength = 0.62;

float shade_at(vec2 xz) {
	if (shade_rect.z <= 0.0) {
		return 0.0;
	}
	vec2 uv = (xz - shade_rect.xy) * shade_rect.z;
	vec2 edge = min(uv, 1.0 - uv);
	float fade = clamp(min(edge.x, edge.y) / shade_rect.w, 0.0, 1.0);
	return textureLod(shade_tex, uv, 0.0).r * fade * shade_strength;
}
