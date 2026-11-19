#version 140

in highp vec2 var_texcoord0;
in mediump vec4 var_color;

out vec4 out_fragColor;

uniform lowp sampler2D texture_sampler;
uniform fs_uniforms
{
    highp vec4 tissue_atlas;     // Atlas center and signed half-extents.
    mediump vec4 tissue_size;    // Portrait half-extents in body radii.
    mediump vec4 tissue_strain;  // Local spring strain and lag.
    mediump vec4 tissue_waves;   // Phase and amplitude of the three- and five-lobed waves.
    mediump vec4 tissue_flow;    // Cytoplasm drift, breathing, and membrane curl.
    mediump vec4 tissue_contact; // Feeding direction, strength, and chewing wave.
    mediump vec4 tissue_wounds;  // Wound phase, severity, and circulation.
    mediump vec4 tissue_pigment; // Absorbed color and its concentration.
    mediump vec4 tissue_fragment; // Enabled, sector angle, half-angle, and quality grade.
};

#include "/main/tissue_deform.glsl"

void main()
{
    highp vec2 atlas_extent = abs(tissue_atlas.zw);
    highp vec2 atlas_local = (var_texcoord0 - tissue_atlas.xy) / atlas_extent;
    bool rotated = tissue_atlas.z < 0.0;
    // Atlas packing rotates clockwise in image space, where Y points down.
    mediump vec2 p = (rotated ? vec2(-atlas_local.y, atlas_local.x) : atlas_local) * 1.24 * tissue_size.xy;
    mediump float bite=0.0, cut=0.0;
    mediump vec2 source;
    if (tissue_size.z > 0.5) {
        // Small animals retain the same inherited spring and breathing as the
        // detailed version. Their small footprint needs no vessel or wound warp.
        vec2 q=p/tissue_flow.z-tissue_strain.zw;
        vec2 strain=tissue_strain.xy;
        source=vec2((1.0-strain.x)*q.x-strain.y*q.y,(1.0+strain.x)*q.y-strain.y*q.x)
            /(1.0-dot(strain,strain));
        float r=max(length(source),0.001);
        vec2 n=source/r;
        vec2 h2=tissue_complex(n,n);
        vec2 h3=tissue_complex(h2,n);
        source/=1.0+min(r,1.2)*(dot(h3,tissue_waves.xy)+dot(n,tissue_flow.xy));
    } else source=tissue_sample(p,bite,cut);
    mediump vec2 sample_point = source / tissue_size.xy;

    mediump float edge = max(abs(sample_point.x), abs(sample_point.y));
    mediump float coverage = 1.0 - smoothstep(0.992, 1.0, edge);
    sample_point = clamp(sample_point, vec2(-1.0), vec2(1.0));
    highp vec2 warped = rotated ? vec2(sample_point.y, -sample_point.x) : sample_point;
    mediump vec4 rgba = texture(texture_sampler, tissue_atlas.xy + atlas_extent * warped);

    if (tissue_fragment.x > 0.5) {
        mediump float theta = atan(sample_point.y, sample_point.x);
        mediump float delta = abs(mod(theta - tissue_fragment.y + TISSUE_TAU * 0.5, TISSUE_TAU) - TISSUE_TAU * 0.5);
        mediump float tear = tissue_fragment.z
            + sin(theta * 13.0 + tissue_wounds.x * 1.7) * 0.022
            + sin(theta * 27.0 - tissue_wounds.x * 0.8) * 0.010;
        mediump float seam = 1.0 - smoothstep(0.012, 0.052, abs(delta - tear));
        mediump vec3 seam_color = tissue_fragment.w >= 2.5 ? vec3(1.0, 0.76, 0.38)
            : tissue_fragment.w >= 1.5 ? vec3(0.86, 0.63, 1.0)
            : tissue_fragment.w >= 0.5 ? vec3(0.66, 0.83, 1.0)
            : vec3(0.82, 0.97, 0.89);
        rgba.rgb = mix(rgba.rgb, seam_color * max(max(rgba.r, rgba.g), rgba.b), seam * 0.72);
        rgba.a *= 1.0 - smoothstep(tear - 0.012, tear + 0.012, delta);
    }

    // Circulation carries accumulated pigment through the folds of the moving membrane.
    mediump float radius2 = dot(source, source);
    mediump float membrane = smoothstep(0.19, 1.05, radius2);
    mediump float brightness = max(max(rgba.r, rgba.g), rgba.b);
    mediump float circulation = dot(source, tissue_flow.xy);
    mediump float stain = tissue_pigment.w * (0.24 + 0.24 * membrane + 0.55 * circulation);
    rgba.rgb = mix(rgba.rgb, tissue_pigment.rgb * brightness, stain);
    if (tissue_size.z <= 0.5) {
        // Work in deformed tissue coordinates so the folds travel with the body.
        mediump vec2 folds = vec2(source.x + 0.36 * source.y * source.y,
                                  source.y - 0.24 * source.x * source.y);
        mediump float bands = sin(28.0 * folds.x + 13.0 * folds.y + 3.0 * circulation);
        mediump float fibers = bands * sin(17.0 * folds.y - 5.0 * folds.x);
        mediump float rim = smoothstep(0.62, 0.92, radius2) * (1.0 - smoothstep(0.94, 1.24, radius2));
        rgba.rgb *= 1.0 + fibers * (0.12 - rim * 0.045);
        rgba.rgb += vec3(0.06, 0.12, 0.13) * (bands * 0.5 + 0.5) * rim * rgba.a;
    }
    mediump float wound = clamp(cut * (0.50 + 0.13 * tissue_wounds.z) * membrane, 0.0, 0.48);
    rgba.rgb = mix(rgba.rgb, vec3(0.56, 0.23, 0.34) * brightness, wound);
    rgba.rgb = min(rgba.rgb * (1.0 + bite * (0.23 + 0.12 * tissue_contact.w)), vec3(rgba.a));
    out_fragColor = rgba * var_color * coverage;
}
