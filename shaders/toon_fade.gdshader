// Растворение точками: включается только на время, пока крона заслоняет игрока.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#define FADE
#include "res://shaders/toon_body.gdshaderinc"
