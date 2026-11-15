// Тени предметов на земле и траве: картинка сверху (scripts/shadows.gd),
// окно вокруг игрока. Одно чтение текстуры; за пределами окна теней нет.
// Земле и дорогам: shade_coords на вершинах, shade_lookup в пикселе —
// картинка читается прямо по интерполированным координатам (так телефон
// читает её раньше, чем начнёт считать пиксель).

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

// На вершинах: где читать картинку теней (xy) и сила тени у края окна (z;
// 0 — теней нет). Всё это линейно по месту, так что интерполяция точна
// (кроме мягкого края окна, где неточность не видна).
vec3 shade_coords(vec2 xz) {
	if (shade_rect.z <= 0.0) {
		return vec3(0.0);
	}
	vec2 uv = (xz - shade_rect.xy) * shade_rect.z;
	vec2 edge = min(uv, 1.0 - uv);
	return vec3(uv, clamp(min(edge.x, edge.y) / shade_rect.w, 0.0, 1.0));
}

// В пикселе: доля тени без учёта силы тени, 0–1.
float shade_lookup(vec3 coords) {
	return texture(shade_tex, coords.xy).r * coords.z;
}
