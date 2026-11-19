#version 140

in highp vec2 var_texcoord0;
in mediump vec4 var_color;

out vec4 out_fragColor;

uniform lowp sampler2D texture_sampler;
uniform fs_uniforms
{
    highp vec4 tissue_atlas;    // Center and signed half-extents. Negative X marks a rotated frame.
    mediump vec4 tissue_motion; // Movement in screen space and two idle waves.
    mediump vec4 tissue_contact;// Contact direction, bite strength, and chewing wave.
    mediump vec4 tissue_pigment;// Absorbed color and its concentration.
};

void main()
{
    highp vec2 atlas_extent = abs(tissue_atlas.zw);
    highp vec2 atlas_local = (var_texcoord0 - tissue_atlas.xy) / atlas_extent;
    bool rotated = tissue_atlas.z < 0.0;
    // Atlas packing rotates clockwise in image space, where Y points down.
    mediump vec2 p = (rotated ? vec2(-atlas_local.y, atlas_local.x) : atlas_local) * 1.24;
    mediump float radius2 = dot(p, p);
    mediump float membrane = smoothstep(0.13, 0.88, radius2);
    mediump vec2 tangent = vec2(-p.y, p.x);

    mediump float pulse = tissue_motion.z * (0.010 + 0.015 * membrane);
    mediump float ripple = (p.x * p.y * tissue_motion.w + (p.x * p.x - p.y * p.y) * tissue_motion.z) * membrane;
    mediump vec2 sample_point = p * (1.0 - pulse) + tangent * (0.050 * ripple);

    // Pull the edge and appendages behind the cell while stretching along its travel axis.
    mediump vec2 travel = tissue_motion.xy;
    mediump float heading = dot(p, travel);
    sample_point += membrane * travel * (0.067 - 0.12 * heading);
    sample_point += p * (dot(travel, travel) * membrane * 0.035);

    // The side touching prey extends and contracts around the contact direction.
    mediump vec2 prey = tissue_contact.xy;
    mediump float forward = dot(p, prey);
    mediump float across = dot(p, vec2(-prey.y, prey.x));
    mediump float focus = smoothstep(0.12, 0.82, forward) * (1.0 - smoothstep(0.12, 0.68, abs(across)));
    mediump float bite = tissue_contact.z * focus;
    sample_point -= bite * (prey * (0.10 + 0.034 * tissue_contact.w) + p * 0.022);

    mediump float edge = max(abs(sample_point.x), abs(sample_point.y));
    mediump float coverage = 1.0 - smoothstep(0.992, 1.0, edge);
    sample_point = clamp(sample_point, vec2(-1.0), vec2(1.0));
    highp vec2 warped = rotated ? vec2(sample_point.y, -sample_point.x) : sample_point;
    mediump vec4 rgba = texture(texture_sampler, tissue_atlas.xy + atlas_extent * warped);

    // Keep the luminosity and alpha of the baked tissue while carrying absorbed color through it.
    mediump float brightness = max(max(rgba.r, rgba.g), rgba.b);
    mediump float stain = tissue_pigment.w * (0.24 + 0.24 * membrane + 0.06 * ripple);
    rgba.rgb = mix(rgba.rgb, tissue_pigment.rgb * brightness, stain);
    rgba.rgb = min(rgba.rgb * (1.0 + bite * (0.23 + 0.12 * tissue_contact.w)), vec3(rgba.a));
    out_fragColor = rgba * var_color * coverage;
}
