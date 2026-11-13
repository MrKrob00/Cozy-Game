// Плоские поверхности (земля вокруг, дорога, дорожки): принимают тени предметов.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#define RECEIVE_SHADE
#include "res://shaders/toon_body.gdshaderinc"
