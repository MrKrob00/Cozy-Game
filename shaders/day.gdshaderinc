// Свет дня, посчитанный вручную: ни источников света Godot, ни карт теней,
// ни постобработки. Одна нормаль, одно скалярное произведение, мягкая граница.
// Параметры ставит автозагрузка Graphics на каждый материал (не глобальные
// uniform: на части телефонов в Compatibility они читаются как ноль).

uniform vec3 day_dir = vec3(0.353, -0.788, -0.504);    // куда светит солнце
uniform vec3 day_sun = vec3(0.7, 0.672, 0.602);        // цвет солнца × яркость
uniform vec3 day_ambient = vec3(0.546, 0.588, 0.665);  // свет неба
uniform float day_saturation = 1.0;                    // насыщенность картинки

// Освещённость поверхности с нормалью n; shade — доля тени (0..1).
vec3 day_light(vec3 n, float shade) {
	float facing = smoothstep(-0.02, 0.06, dot(n, -day_dir));
	return day_ambient + day_sun * (facing * (1.0 - shade));
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
