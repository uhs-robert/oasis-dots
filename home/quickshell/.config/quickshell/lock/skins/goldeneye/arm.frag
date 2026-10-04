// home/quickshell/.config/quickshell/lock/skins/goldeneye/arm.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o arm.frag.qsb arm.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float span_x;
    float span_y;
    float reach;
    float clip;
};
layout(binding = 1) uniform sampler2D source;

float side(vec2 p, vec2 a, vec2 b) {
    vec2 e = b - a;
    return (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / length(e);
}

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec2 p = (qt_TexCoord0 - 0.5) * vec2(span_x, span_y) + 0.5;
    vec2 beyond = abs(p - clamp(p, 0.0, 1.0));
    if (beyond.x + beyond.y > 0.0) c *= reach;
    vec2 q = p * vec2(1020.0, 720.0);
    float d = max(max(side(q, vec2(63.0, 0.0), vec2(0.0, 115.0)), side(q, vec2(1020.0, 152.0), vec2(960.0, 0.0))), max(side(q, vec2(960.0, 720.0), vec2(1020.0, 568.0)), side(q, vec2(0.0, 617.0), vec2(130.0, 720.0))));
    c *= 1.0 - clip * clamp(0.5 + d, 0.0, 1.0);
    fragColor = c * qt_Opacity;
}
