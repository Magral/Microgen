// Local Y is up, and one unit is the organism's simulation radius.
const float TISSUE_TAU = 6.283185307;

vec2 tissue_complex(vec2 a, vec2 b)
{
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

float tissue_bite(vec2 p)
{
    vec2 prey = tissue_contact.xy;
    float forward = dot(p, prey);
    float across = abs(dot(p, vec2(-prey.y, prey.x)));
    return tissue_contact.z * smoothstep(0.10, 0.78, forward) * (1.0 - smoothstep(0.16, 0.78, across));
}

float tissue_damage(vec2 p)
{
    if (tissue_wounds.y <= 0.0) return 0.0;
    float phase = tissue_wounds.x;
    float theta = -atan(p.y, p.x + 0.00001) - phase;
    float sector = floor(theta * (5.0 / TISSUE_TAU) + 0.5);
    float index = mod(sector, 5.0);
    float offset = abs(theta - sector * (TISSUE_TAU / 5.0) - 0.16 * sin(index * 4.73 + phase));
    float width = (0.30 + 0.055 * sin(index * 2.83 + phase)) * 1.8;
    float depth = tissue_wounds.y * (0.61 + 0.08 * sin(index * 3.17 + phase));
    float ragged = 0.80 + 0.20 * cos(offset * 37.0 + index * 2.2);
    return depth * (1.0 - smoothstep(0.0, width, offset)) * ragged;
}

// Undo spring strain and local flows before sampling tissue or drawing anchored organs.
vec2 tissue_sample(vec2 p, out float bite, out float cut)
{
    p /= tissue_flow.z;
    bite = tissue_bite(p);
    p -= bite * (tissue_contact.xy * (0.20 + 0.072 * tissue_contact.w) + p * 0.038);

    float depth = min(length(p), 1.2);
    float interior = 1.0 - smoothstep(0.12, 0.85, depth);
    p -= tissue_strain.zw * (1.0 - depth * 0.55) + tissue_flow.xy * interior;
    vec2 strain = tissue_strain.xy;
    vec2 q = vec2((1.0 - strain.x) * p.x - strain.y * p.y,
        (1.0 + strain.x) * p.y - strain.y * p.x) / (1.0 - dot(strain, strain));

    float radius = length(q);
    depth = min(radius, 1.2);
    vec2 n = q / max(radius, 0.0001);
    vec2 tangent = vec2(-n.y, n.x);
    vec2 h2 = tissue_complex(n, n);
    vec2 h3 = tissue_complex(h2, n);
    vec2 h5 = tissue_complex(h3, h2);
    float swell = dot(tissue_flow.xy, n);
    float wave = 1.0 + depth * (dot(tissue_waves, vec4(h3, h5)) + swell);
    float curl = depth * (0.035 * tissue_flow.w * h2.y + 0.42 * dot(tissue_flow.xy, tangent));
    q = (q - tangent * (radius * curl)) / wave;
    cut = tissue_damage(q);
    return q / (1.0 - cut);
}

vec2 tissue_sample(vec2 p)
{
    float bite, cut;
    return tissue_sample(p, bite, cut);
}
