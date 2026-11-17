shader_type canvas_item;
render_mode unshaded;
uniform float fluid_time=0.0;
uniform vec2 world_origin=vec2(0.0);
uniform vec2 viewport_size=vec2(1280.0,720.0);
uniform float boundary_phase=0.0;
uniform sampler2D flow_map : repeat_enable, filter_linear;
void fragment() {
	vec2 world=world_origin+UV*viewport_size;
	float t=fluid_time;
	vec2 uv=world*0.00072;
	vec3 far_layer=texture(flow_map,uv+vec2(t*0.006,-t*0.003)).rgb;
	vec3 near_layer=texture(flow_map,uv*1.73+vec2(-t*0.004,t*0.005)+vec2(far_layer.r*0.08)).rgb;
	float border=2860.0+sin(world.y/650.0+boundary_phase)*350.0+sin(world.y/210.0)*100.0;
	float toxic=smoothstep(border-200.0,border+200.0,world.x);
	vec3 deep=mix(vec3(0.022,0.105,0.160),vec3(0.044,0.119,0.095),toxic);
	vec3 haze=mix(vec3(0.035,0.115,0.145),vec3(0.095,0.123,0.044),toxic);
	float caustic=far_layer.g*0.65+near_layer.g*0.35;
	vec3 water=deep+haze*(far_layer.r*0.9+near_layer.b*0.12);
	water+=mix(vec3(0.10,0.33,0.38),vec3(0.22,0.31,0.13),toxic)*caustic*0.30;
	float shaft=0.5+0.5*sin(UV.x*5.0+UV.y*1.4+t*0.025+far_layer.r);
	water+=vec3(0.025,0.065,0.075)*shaft*shaft*(1.0-UV.y)*0.8;
	vec2 lens=(UV-vec2(0.48,0.45))*vec2(1.1,0.8);
	water*=1.0-dot(lens,lens)*0.42;
	COLOR=vec4(water,1.0);
}
