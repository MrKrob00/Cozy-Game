// Свет дня, посчитанный вручную: ни источников света Godot, ни карт теней,
// ни постобработки. Одна нормаль, одно скалярное произведение, мягкая граница.
// Параметры ставит автозагрузка Graphics на каждый материал (не глобальные
// uniform: на части телефонов в Compatibility они читаются как ноль).

uniform vec3 day_dir = vec3(0.353, -0.788, -0.504);    // куда светит солнце
uniform vec3 day_sun = vec3(0.7, 0.672, 0.602);        // цвет солнца × яркость
uniform vec3 day_ambient = vec3(0.546, 0.588, 0.665);  // свет неба (сверху)
uniform vec3 day_bounce = vec3(0.50, 0.46, 0.32);      // тёплый отражённый свет от земли (снизу)
uniform vec3 day_glow = vec3(0.30, 0.12, 0.02);        // тёплая кайма на границе света и тени
uniform float day_saturation = 1.0;                    // насыщенность картинки
// Дымка по глубине (Firewatch: «туман добавляет глубину и расстояние»):
// далёкое растворяется в цвете неба. Цвет — линейный.
uniform vec3 haze_color = vec3(0.39, 0.74, 0.96);
uniform vec2 haze_range = vec2(30.0, 95.0);            // где начинается и где максимальна, метры
uniform float haze_max = 0.55;

// Освещённость поверхности с нормалью n; shade — доля тени (0..1).
// Уютный свет из трёх частей:
//   небо и земля — заполняющий свет: сверху прохладный, снизу тёплый;
//   солнце — тёплое, с мягкой границей в два тона;
//   тёплая кайма там, где свет переходит в тень (как на закатных иллюстрациях).
vec3 day_light(vec3 n, float shade) {
	float ndl = dot(n, -day_dir);
	float facing = smoothstep(-0.02, 0.06, ndl);
	vec3 fill = mix(day_bounce, day_ambient, clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
	float rim = smoothstep(-0.3, 0.0, ndl) * (1.0 - smoothstep(0.0, 0.35, ndl));
	float sunlit = facing * (1.0 - shade);
	return fill + day_sun * sunlit + day_glow * rim * (1.0 - shade * 0.7);
}

// Доля дымки для точки на расстоянии distance от камеры.
float day_haze(float distance) {
	return smoothstep(haze_range.x, haze_range.y, distance) * haze_max;
}

// Насыщенность: заросший участок блёклый, выкошенный — яркий. Считается
// в пространстве, близком к экранному (корень вместо гаммы 2,2), как прежняя
// постобработка: в линейном цвете приглушённая трава выглядит белёсой.
vec3 day_grade(vec3 c) {
	vec3 screen = sqrt(max(c, vec3(0.0)));
	float luma = dot(screen, vec3(0.2126, 0.7152, 0.0722));
	screen = max(mix(vec3(luma), screen, day_saturation), vec3(0.0));
	return screen * screen;
}
