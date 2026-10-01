// home/quickshell/.config/quickshell/lock/skins/goldeneye/static.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o static.frag.qsb static.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float level;
    float tick;
};
layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 cell = floor(uv * vec2(256.0, 194.0));
    float n = hash(cell + vec2(tick * 7.13, tick * 3.77));
    float m = hash(cell.yx + vec2(tick * 1.91, 5.1));
    float hand = 0.0;
    for (int i = 0; i < 4; i++) {
        vec2 off = vec2(i < 2 ? -0.012 : 0.012, (i == 0 || i == 2) ? -0.012 : 0.012);
        hand = max(hand, texture(source, uv + off).a);
    }
    hand = smoothstep(0.04, 0.25, hand);
    float band = 1.0 - smoothstep(0.015, 0.045, abs(uv.y - 0.5));
    float dense = 0.09 + band * 0.35 + hand * 0.55;
    float on = step(1.0 - dense, n);
    float white = clamp(hand + band * 0.6, 0.0, 1.0) * step(0.5, m);
    vec3 col = mix(vec3(0.25, 0.85, 0.30) * (0.4 + 0.6 * m), vec3(1.0), white);
    float a = on * level * (0.35 + 0.65 * max(hand, band));
    fragColor = vec4(col * a, a) * qt_Opacity;
}
