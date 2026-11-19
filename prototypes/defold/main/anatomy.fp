#version 140

in highp vec2 var_texcoord0;
in mediump vec4 var_color;
out vec4 out_fragColor;

uniform fs_uniforms
{
    mediump vec4 anatomy_ranks;   // Tentacle count, cilia, spikes, devour.
    mediump vec4 anatomy_glands;  // Acid, enzymes, and infection vesicle counts, barrier rank.
    mediump vec4 anatomy_action;  // Clock, mouth opening, lash, ciliary strike.
    mediump vec4 anatomy_barrier; // Block flash, distress, barrier charge.
    mediump vec4 anatomy_shape_12;
    mediump vec4 anatomy_shape_34;
    mediump vec4 anatomy_shape_56;
    mediump vec4 anatomy_shape_78;
    mediump vec4 anatomy_shape_rest;
};

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

void main()
{
    // Same 2.10 radius as the Lua node bounds. Local positive X points toward prey.
    vec2 p = (var_texcoord0 * 2.0 - 1.0) * 2.10;
    float time = anatomy_action.x;
    float angle = atan(p.y, p.x + 0.0001);
    float r = length(p);
    float feather = clamp(fwidth(r), 0.009, 0.05);
    vec2 normal = p / max(0.0001, r);
    float contour = silhouette(normal) * (1.0 + 0.015 * sin(time * 2.8));
    float membrane = r - contour;
    vec4 result = vec4(0.0);

    if (anatomy_ranks.x > 0.0) {
        vec2 sector = radial_cell(angle - 0.52, anatomy_ranks.x);
        float index = mod(sector.y, anatomy_ranks.x);
        float wag = sin(time * 4.6 - index * 1.52 + r * 7.4);
        float extension = 0.58 + 0.19 * anatomy_action.z + 0.042 * cos(index * 2.1 + time * 3.2);
        float u = clamp((membrane + 0.10) / extension, 0.0, 1.0);
        float sway = (0.20 * wag + 0.058) * u * u;
        float distance = (sector.x - sway) * r;
        float envelope = smoothstep(-0.16, -0.075, membrane) * (1.0 - smoothstep(extension - 0.10, extension, membrane));
        float width = mix(0.060, 0.012, u);
        float flesh = line_mask(distance, width, feather) * envelope;
        float rim = line_mask(distance + width * 0.28, width * 0.41, feather * 0.84) * envelope;
        result = layer(result, vec3(0.20, 0.48, 0.38), flesh * 0.89);
        result = layer(result, vec3(0.66, 0.92, 0.72), rim * (0.62 + 0.17 * anatomy_action.z));
    }

    if (anatomy_ranks.y > 0.0) {
        float phase = (angle + 1.05) / 0.30;
        float index = clamp(floor(phase + 0.5), 0.0, 7.0);
        float u = clamp(membrane * 3.5, 0.0, 1.0);
        float wave = sin(time * 12.5 - index * 0.74 + u * 3.5);
        float cilium = 0.30 * (phase - index) - wave * u * 0.095;
        float reach = 0.20 + 0.07 * wave + 0.16 * anatomy_action.w + min(anatomy_ranks.y, 6.0) * 0.008;
        float envelope = smoothstep(-0.09, -0.035, membrane) * (1.0 - smoothstep(reach - 0.07, reach, membrane));
        float fiber = line_mask(cilium * r, mix(0.026, 0.008, u), feather) * envelope;
        result = layer(result, vec3(0.72, 0.92, 0.83), fiber * 0.71);
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
        result = gland(result, p, angle, anatomy_glands.x, 0.75, 0.69, min(0.15, contour * 0.23), vec3(0.68, 0.85, 0.40), time);
    }
    if (anatomy_glands.y > 0.0) {
        result = gland(result, p, angle, anatomy_glands.y, 1.59, 0.54, min(0.125, contour * 0.21), vec3(0.96, 0.68, 0.39), time);
    }
    if (anatomy_glands.z > 0.0) {
        result = gland(result, p, angle, anatomy_glands.z, 1.88, 0.76, min(0.13, contour * 0.21), vec3(0.82, 0.51, 0.72), time);
    }

    // The lip is anchored on the outer membrane. The throat opens into the body.
    float aperture = anatomy_action.y;
    float mouth_width = 0.045 + 0.24 * aperture + min(3.0, anatomy_ranks.w) * 0.012;
    float front = anatomy_shape_rest.y;
    vec2 mouth = p - vec2(front * (0.84 - 0.13 * aperture), 0.0);
    mouth.x += mouth.y * mouth.y * 0.63;
    float jaw = length(mouth / vec2(mouth_width * min(1.0, front * 1.2), min(0.26, front * 0.34) + 0.06 * aperture));
    result = layer(result, vec3(0.23, 0.45, 0.36), (1.0 - smoothstep(0.80, 1.38, jaw)) * 0.72);
    result = layer(result, vec3(0.035, 0.056, 0.060), (1.0 - smoothstep(0.84, 1.03, jaw)) * 0.94);
    float lit_lip = 0.45 + clamp(mouth.y * 1.8 - mouth.x, -0.42, 0.46);
    result = layer(result, vec3(0.70, 0.90, 0.76), line_mask(jaw - 1.02, 0.080, 0.17) * lit_lip);

    if (anatomy_glands.w > 0.0) {
        float block = anatomy_barrier.x;
        float charge = anatomy_barrier.z;
        float curl = 0.055 * sin(angle * 4.0 + time * 2.0);
        float rim = membrane - 0.13 - curl - block * 0.14;
        float shield = line_mask(rim, 0.025 + 0.027 * block, feather * 1.7);
        float segments = 0.44 + 0.56 * smoothstep(-0.75, 0.62, cos(angle * 5.0 + 0.7));
        result = layer(result, vec3(0.55, 0.89, 0.96), shield * segments * (0.11 + 0.42 * charge + 0.35 * block));
    }

    if (anatomy_barrier.y > 0.0) {
        float distress = anatomy_barrier.y;
        float wounds = smoothstep(0.45, 0.90, sin(angle * 3.0 + sin(angle * 2.0) * 0.8) + 0.25 * sin(angle * 11.0));
        float depth = line_mask(membrane + 0.12, 0.070 + 0.045 * distress, 0.062);
        float perfusion = 0.69 + 0.31 * sin(time * 7.0 + angle * 2.0);
        result = layer(result, vec3(0.60, 0.23, 0.32), wounds * depth * perfusion * distress * 0.78);
    }
    out_fragColor = result * var_color;
}
