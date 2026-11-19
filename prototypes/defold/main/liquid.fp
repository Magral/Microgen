#version 140

in highp vec2 var_uv;
in highp vec2 var_world;
in highp vec4 var_optical;
out vec4 out_fragColor;

uniform mediump sampler2D texture_sampler;
uniform fs_uniforms {
    highp vec4 fluid_view;
    highp vec4 fluid_stage;
};

mediump vec3 optical_sample(highp vec2 p) {
    return texture(texture_sampler,vec2(p.x,1.0-p.y)).rgb;
}

void main() {
    highp vec2 world = var_world;
    highp float time = fluid_stage.x;

    mediump vec3 far_layer = optical_sample(var_optical.xy);
    mediump vec3 near_layer = optical_sample(var_optical.zw + far_layer.r * 0.08);

    // The biome boundary follows the collision world's seed, like the Godot shader.
    highp float relative = world.x-fluid_stage.z;
    mediump float toxic = step(0.0,relative);
    if (abs(relative) < 650.0) {
        highp float bend = sin(world.y / 650.0 + fluid_stage.y) * 350.0 + sin(world.y / 210.0) * 100.0;
        toxic = smoothstep(-200.0,200.0,relative-bend);
    }
    mediump vec3 deep = mix(vec3(0.022,0.105,0.160),vec3(0.044,0.119,0.095),toxic);
    mediump vec3 haze = mix(vec3(0.035,0.115,0.145),vec3(0.095,0.123,0.044),toxic);
    mediump float caustic = far_layer.g * 0.65 + near_layer.g * 0.35;
    mediump vec3 water = deep + haze * (far_layer.r * 0.90 + near_layer.b * 0.06);
    water += mix(vec3(0.1,0.33,0.38),vec3(0.22,0.31,0.13),toxic) * caustic * 0.30;
    // The flow atlas packs suspended grains with two independently drifting depths.
    mediump float suspended = smoothstep(0.28, 0.72, near_layer.b);
    suspended += smoothstep(0.32, 0.76, far_layer.b) * 0.38;
    water += mix(vec3(0.07,0.23,0.25),vec3(0.21,0.24,0.075),toxic) * suspended * (0.24 + caustic * 0.28);
    mediump float shaft = 0.5 + 0.5 * sin(var_uv.x * 5.0 + var_uv.y * 1.4 + time * 0.025 + far_layer.r);
    water += vec3(0.025,0.065,0.075) * shaft * shaft * (1.0-var_uv.y) * 0.8;
    mediump vec2 lens = (var_uv-vec2(0.48,0.45)) * vec2(1.1,0.8);
    water *= 1.0 - dot(lens,lens) * 0.42;
    out_fragColor = vec4(water,1.0);
}
