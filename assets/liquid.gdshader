shader_type canvas_item;
render_mode unshaded;

uniform float fluid_time = 0.0;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 viewport_size = vec2(1280.0,720.0);
uniform float boundary_phase = 0.0;

float hash21(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float smooth_noise(vec2 p) {
	vec2 cell=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(cell),hash21(cell+vec2(1.0,0.0)),f.x),mix(hash21(cell+vec2(0.0,1.0)),hash21(cell+vec2(1.0)),f.x),f.y);
}
void fragment() {
	vec2 world=world_origin+UV*viewport_size;
	vec2 p=world*0.0028;
	float t=fluid_time;
	vec2 drift=vec2(sin(p.y*0.8+t*0.19),cos(p.x*0.65-t*0.15));
	float haze=smooth_noise(p*1.7+drift*0.8+vec2(t*0.055,-t*0.03));
	float fine=smooth_noise(p*4.2-drift*0.4+vec2(-t*0.04,t*0.065));
	float threads=pow(0.5+0.5*sin(p.x*1.7+p.y*1.2+haze*5.0-t*0.28),9.0);
	float border=2860.0+sin(world.y/650.0+boundary_phase)*350.0+sin(world.y/210.0)*100.0;
	float toxic=smoothstep(border-200.0,border+200.0,world.x);
	vec3 deep=mix(vec3(0.018,0.064,0.091),vec3(0.042,0.079,0.065),toxic);
	vec3 tint=mix(vec3(0.025,0.078,0.098),vec3(0.067,0.083,0.036),toxic);
	vec3 water=deep+tint*(haze*0.7+fine*0.17)+vec3(0.025,0.063,0.069)*threads*0.28;
	COLOR=vec4(water,1.0);
}
