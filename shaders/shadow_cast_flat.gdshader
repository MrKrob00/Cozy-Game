// Тень готовой модели со скелетом (персонажи, зверьки): в UV у неё текстура,
// поэтому землёй под ней считается её начало координат.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, world_vertex_coords;

#define FLAT_BASE
#include "res://shaders/shadow_cast_body.gdshaderinc"
