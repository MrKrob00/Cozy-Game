// Цветы: качаются на ветру и приминаются косилкой.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#define PLANT
#include "res://shaders/toon_body.gdshaderinc"
