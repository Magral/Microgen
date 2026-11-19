#version 140

in highp vec2 var_texcoord0;
in mediump vec4 var_color;
out vec4 out_fragColor;

uniform fs_uniforms
{
    mediump vec4 anatomy_ranks;
    mediump vec4 anatomy_glands;
    mediump vec4 anatomy_action;
    mediump vec4 anatomy_barrier;
    mediump vec4 anatomy_mouth;
    mediump vec4 anatomy_body;
    mediump vec4 anatomy_edge;
    mediump vec4 anatomy_lip;
    mediump vec4 anatomy_growth;
    mediump vec4 anatomy_appendages;
    mediump vec4 tissue_strain;
    mediump vec4 tissue_waves;
    mediump vec4 tissue_flow;
    mediump vec4 tissue_contact;
    mediump vec4 tissue_wounds;
    mediump vec4 anatomy_shape_12;
    mediump vec4 anatomy_shape_34;
    mediump vec4 anatomy_shape_56;
    mediump vec4 anatomy_shape_78;
    mediump vec4 anatomy_shape_rest;
};

#include "/main/tissue_deform.glsl"

const float TAU = 6.283185307;

vec4 layer(vec4 base, vec3 pigment, float alpha)
{
    return vec4(pigment * alpha, alpha) + base * (1.0 - alpha);
}

float line_mask(float signed_distance, float width, float feather)
{
    return 1.0 - smoothstep(width - feather, width + feather, abs(signed_distance));
}

// Draw the nearest anchor in the radial array. Every repeat ends before its neighbor.
vec2 radial_cell(float angle, float count)
{
    float phase = angle / TAU * count;
    float index = floor(phase + 0.5);
    return vec2((phase - index) * TAU / count, index);
}

vec2 rotate_complex(vec2 a, vec2 b)
{
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

float silhouette(vec2 normal)
{
    vec2 h2 = rotate_complex(normal, normal);
    vec2 h3 = rotate_complex(h2, normal);
    vec2 h4 = rotate_complex(h2, h2);
    vec2 h5 = rotate_complex(h4, normal);
    vec2 h6 = rotate_complex(h3, h3);
    vec2 h7 = rotate_complex(h4, h3);
    vec2 h8 = rotate_complex(h4, h4);
    return anatomy_shape_rest.x + dot(anatomy_shape_12, vec4(normal, h2))
        + dot(anatomy_shape_34, vec4(h3, h4)) + dot(anatomy_shape_56, vec4(h5, h6))
        + dot(anatomy_shape_78, vec4(h7, h8));
}

vec4 gland(vec4 base, vec2 p, float angle, float count, float offset,
           float radius, float size, vec3 pigment, float time)
{
    vec2 sector = radial_cell(angle - offset, count);
    float anchor = sector.y * TAU / count + offset;
    vec2 normal = vec2(cos(anchor), sin(anchor));
    vec2 origin = radius * silhouette(normal) * normal;
    float pulse = 1.0 + 0.12 * sin(time * 2.7 + anchor * 1.9);
    vec2 body = (p - origin) / (size * pulse);
    float r = length(body);
    base = layer(base, pigment * 0.34, (1.0 - smoothstep(0.56, 1.05, r)) * 0.61);
    base = layer(base, pigment, line_mask(r - 0.81, 0.14, 0.15) * 0.31);
    float kernel = 1.0 - smoothstep(0.05, 0.69, length(body + vec2(0.12, -0.20)));
    return layer(base, pigment, kernel * 0.58);
}

void sample_segment(vec2 p, vec2 a, vec2 b, float index, inout vec3 nearest)
{
    vec2 d = b-a;
    float t = clamp(dot(p-a,d)/max(dot(d,d),0.000001),0.0,1.0);
    vec2 off = p-a-t*d;
    float square = dot(off,off);
    if (square < nearest.x) {
        vec2 normal = vec2(-d.y,d.x) / max(length(d),0.0001);
        nearest = vec3(square,(index+t)/9.0,dot(off,normal));
    }
}

vec4 draw_ribbon()
{
    vec2 p = (var_texcoord0-0.5)*anatomy_mouth.xy;
    vec3 nearest = vec3(64.0,0.0,0.0);
    sample_segment(p, anatomy_shape_12.xy, anatomy_shape_12.zw, 0.0, nearest);
    sample_segment(p, anatomy_shape_12.zw, anatomy_shape_34.xy, 1.0, nearest);
    sample_segment(p, anatomy_shape_34.xy, anatomy_shape_34.zw, 2.0, nearest);
    sample_segment(p, anatomy_shape_34.zw, anatomy_shape_56.xy, 3.0, nearest);
    sample_segment(p, anatomy_shape_56.xy, anatomy_shape_56.zw, 4.0, nearest);
    sample_segment(p, anatomy_shape_56.zw, anatomy_shape_78.xy, 5.0, nearest);
    sample_segment(p, anatomy_shape_78.xy, anatomy_shape_78.zw, 6.0, nearest);
    sample_segment(p, anatomy_shape_78.zw, anatomy_shape_rest.xy, 7.0, nearest);
    sample_segment(p, anatomy_shape_rest.xy, anatomy_shape_rest.zw, 8.0, nearest);
    float t = nearest.y;
    float width = anatomy_mouth.z * mix(0.65,0.055,t*t);
    float feather = max(0.006,1.4 / anatomy_mouth.w);
    float taper = smoothstep(0.0,0.09,t) * (1.0-smoothstep(0.92,1.0,t));
    float alpha = (1.0-smoothstep(width-feather,width+feather,sqrt(nearest.x)))*taper;
    float sheen = line_mask(nearest.z-width*0.24,width*0.22,feather)*taper;
    vec4 result = layer(vec4(0.0), anatomy_edge.rgb * mix(0.42,0.68,t), alpha * 0.89);
    return layer(result, anatomy_edge.rgb * (0.94+0.14*anatomy_edge.a),sheen*(0.46+0.28*anatomy_edge.a));
}

void main()
{
    if (anatomy_growth.w > 0.5) {
        out_fragColor = draw_ribbon()*var_color;
        return;
    }
    vec2 screen = (var_texcoord0*2.0-1.0)*2.10;
    if (dot(screen,screen)>3.75) discard;
    vec2 p = tissue_sample(screen);
    float time = anatomy_action.x;
    float angle = atan(p.y,p.x+0.0001);
    float r = length(p);
    float feather = clamp(1.3*anatomy_mouth.w,0.006,0.05);
    vec2 normal = p / max(0.0001,r);
    float contour = silhouette(normal);
    float membrane = r-contour;
    vec4 result = vec4(0.0);

    if (anatomy_appendages.x > 0.0 && membrane > -0.17) {
        float count = anatomy_appendages.x;
        vec2 sector = radial_cell(angle-anatomy_action.z,count);
        float index = mod(-sector.y,count);
        float has_path = mod(floor(anatomy_lip.w*exp2(-index)),2.0);
        float reach = (0.72+0.17*anatomy_growth.x) * contour;
        float u = clamp((membrane+0.15)/(reach+0.15),0.0,1.0);
        float flex = 0.22*sin(time*4.6-index*1.52+u*6.4)*u*u;
        float pos = (sector.x-flex)*r;
        float width = mix(0.052,0.008,u);
        float envelope = smoothstep(-0.17,-0.081,membrane)
            * (1.0-smoothstep(reach-0.095,reach,membrane)) * (1.0-has_path);
        float flesh = line_mask(pos,width,feather) * envelope;
        float sheen = line_mask(pos+width*0.25,width*.30,feather) * envelope;
        result = layer(result,anatomy_body.rgb*0.61,flesh*.89);
        result = layer(result,anatomy_edge.rgb,sheen*.58);
    }

    if (anatomy_appendages.y > 0.0 && p.x > 0.11) {
        float phase = (angle+1.2)/0.34;
        float index = clamp(floor(phase+0.5),0.0,7.0);
        float u = clamp(membrane*4.0,0.0,1.0);
        float wave = sin(time*12.5-index*.74+u*3.5);
        float center = (0.34*(phase-index)-wave*u*.11)*r;
        float reach = 0.19+0.07*wave+min(anatomy_appendages.y,6.0)*0.012;
        float mask = smoothstep(-0.09,-0.024,membrane) * (1.0-smoothstep(reach-0.060,reach,membrane));
        result = layer(result,anatomy_edge.rgb,line_mask(center,mix(.024,.008,u),feather)*mask*.76);
    }

    if (anatomy_appendages.z > 0.0 && p.x < -0.03) {
        float sector = angle+step(angle,0.0)*TAU-3.14159265;
        float fiber = floor(sector/.55+.5);
        float curl = sin(time*6.0+membrane*8.6+fiber*1.9);
        float u = clamp((membrane+.1)*1.35,0.0,1.0);
        float axis = (sector-fiber*.55-curl*u*.21)*r;
        float mask = step(abs(fiber),1.0)*smoothstep(-.10,-.03,membrane)*(1.0-smoothstep(.49,.74,membrane));
        result=layer(result,anatomy_edge.rgb,line_mask(axis,mix(.039,.012,u),feather)*mask*.65);
    }

    if (anatomy_appendages.w > 0.0) {
        vec2 sector=radial_cell(angle-anatomy_action.z,8.0);
        float phase=sin(time*4.0+sector.y*2.0);
        float reach=.19+phase*.037;
        float mask=smoothstep(-.07,-.02,membrane)*(1.0-smoothstep(reach-.041,reach,membrane));
        result=layer(result,anatomy_edge.rgb,line_mask(sector.x*r,.019,feather)*mask*.57);
    }

    if (anatomy_ranks.x > 0.0) {
        float count = min(15.0,8.0+anatomy_ranks.x);
        vec2 sector = radial_cell(angle-anatomy_action.z,count);
        float plate = length(vec2((membrane+0.055)*10.0,sector.x*4.0));
        result = layer(result, anatomy_body.rgb*0.52, (1.0-smoothstep(0.70,1.0,plate))*0.46);
        result = layer(result, anatomy_edge.rgb, line_mask(plate-0.87,0.079,0.12)*0.32);
    }

    if (anatomy_ranks.z > 0.0) {
        vec2 sector = radial_cell(angle - 0.17, min(12.0, 5.0 + anatomy_ranks.z));
        float reach = 0.32 + 0.06 * cos(sector.y * 3.4) + min(anatomy_ranks.z, 8.0) * 0.014;
        float u = clamp((membrane + 0.085) / reach, 0.0, 1.0);
        float envelope = smoothstep(-0.11, -0.06, membrane) * (1.0 - smoothstep(reach - 0.045, reach, membrane));
        float center = sector.x * r - u * u * 0.055;
        float barb = line_mask(center, (1.0 - u) * 0.074, feather) * envelope;
        result = layer(result, vec3(0.60, 0.41, 0.21), barb * 0.82);
        float sheen = line_mask(center + 0.012, 0.019 * (1.0 - u * 0.5), feather) * envelope;
        result = layer(result, vec3(0.98, 0.76, 0.47), sheen * 0.73);
    }

    if (anatomy_glands.x > 0.0) {
        result = gland(result, p, angle, 3.0 + anatomy_growth.y * 3.0, 0.75 + anatomy_action.z, 0.69,
            min(0.16, contour * 0.23), mix(vec3(0.68,0.85,0.40), vec3(0.89,1.0,0.60),anatomy_action.w), time);
    }
    if (anatomy_glands.y > 0.0) {
        result = gland(result, p, angle, 4.0, 1.59 + anatomy_action.z, 0.54,
            min(0.125, contour * 0.21), vec3(0.96,0.68,0.39), time);
    }
    if (anatomy_glands.z > 0.0) {
        result = gland(result, p, angle, 3.0 + anatomy_growth.z * 3.0, 1.88 + anatomy_action.z, 0.76,
            min(0.15, contour * 0.22), vec3(0.82,0.51,0.72) + vec3(0.03,0.07,0.05)*min(3.0,anatomy_barrier.w), time);
    }

    // The front is a pliant pair of lips over the working throat. Both are
    // evaluated in the same deformed membrane coordinates as the organs.
    float aperture = anatomy_action.y;
    float across = p.y / max(0.01,anatomy_mouth.y);
    if (abs(across) <= 1.075) {
        float arch = pow(max(0.0,1.0-across*across),0.47);
        float depth = anatomy_mouth.x - 0.044*across*across;
        float upper = depth + anatomy_mouth.z * arch * 0.38;
        float lower = depth - anatomy_mouth.z * arch * 1.42;
        float fade = 1.0-smoothstep(0.87,1.07,abs(across));
        float throat = smoothstep(lower-feather,lower+feather,p.x)
            * (1.0-smoothstep(upper-feather,upper+feather,p.x))*fade;
        float chamber = smoothstep(lower-0.048,lower-0.012,p.x)
            * (1.0-smoothstep(upper+0.01,upper+0.064,p.x))*fade;
        float front_lip=line_mask(p.x-upper,0.017+0.013*aperture,feather)*fade;
        float rear_lip=line_mask(p.x-lower,0.018+0.017*aperture,feather)*fade;
        result=layer(result,anatomy_body.rgb*0.55,chamber*0.72);
        result=layer(result,vec3(0.026,0.033,0.044),throat*0.94);
        result=layer(result,anatomy_lip.rgb,(front_lip*0.58+rear_lip*0.46)*(0.76+aperture*0.24));
        float teeth = smoothstep(0.6,0.94,cos(across*(18.0+min(5.0,anatomy_ranks.z))));
        result=layer(result,mix(anatomy_lip.rgb,vec3(0.94,0.88,0.61),0.68),
            teeth*throat*line_mask(p.x-upper+0.026,0.022,feather)*step(1.0,anatomy_ranks.z)*aperture);
    }

    if (anatomy_ranks.w > 0.0) {
        float pulse = 0.5 + 0.5*sin(time*5.0-r*14.0);
        result = layer(result,anatomy_edge.rgb,line_mask(membrane+0.13,0.013,feather)*pulse*0.31);
    }

    if (anatomy_glands.w > 0.0) {
        float block = anatomy_barrier.x;
        float charge = min(1.0,anatomy_glands.w*0.3);
        float curl = 0.055 * sin(angle * 4.0 + time * 2.0);
        float rim = membrane - 0.13 - curl - block * 0.14;
        float shield = line_mask(rim, 0.025 + 0.027 * block, feather * 1.7);
        float segments = 0.44 + 0.56 * smoothstep(-0.75, 0.62, cos(angle * 5.0 + 0.7));
        result = layer(result, vec3(0.55, 0.89, 0.96), shield * segments * (0.11 + 0.42 * charge + 0.35 * block));
    }

    if (anatomy_body.w > 0.0) {
        float distress = anatomy_body.w;
        float wounds = smoothstep(0.45, 0.90, sin(angle * 3.0 + sin(angle * 2.0) * 0.8) + 0.25 * sin(angle * 11.0));
        float depth = line_mask(membrane + 0.12, 0.070 + 0.045 * distress, 0.062);
        float perfusion = 0.69 + 0.31 * sin(time * 7.0 + angle * 2.0);
        result = layer(result, vec3(0.60, 0.23, 0.32), wounds * depth * perfusion * distress * 0.78);
    }
    out_fragColor = result * var_color;
}
