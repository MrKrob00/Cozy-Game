// Тень предмета для картинки теней (scripts/shadows.gd): каждая вершина
// сдвигается вдоль солнечного луча на землю (y = 0), камера смотрит сверху.
// Свет — один параметр: поворот солнца ничего не перестраивает.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, world_vertex_coords;

#include "res://shaders/shadow_cast_body.gdshaderinc"
