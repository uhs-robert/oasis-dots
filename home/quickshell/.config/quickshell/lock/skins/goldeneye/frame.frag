// home/quickshell/.config/quickshell/lock/skins/goldeneye/frame.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o frame.frag.qsb frame.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float span_x;
    float span_y;
    float reach;
};
layout(binding = 1) uniform sampler2D color_src;
layout(binding = 2) uniform sampler2D mask_src;

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * vec2(span_x, span_y) + 0.5;
    vec2 q = clamp(p, vec2(0.005, 0.005), vec2(0.995, 0.995));
    vec3 c = texture(color_src, q).rgb;
    float m = texture(mask_src, q).r;
    vec2 beyond = abs(p - clamp(p, 0.0, 1.0));
    if (beyond.x + beyond.y > 0.0) m *= reach;
    fragColor = vec4(min(c, vec3(m)), m) * qt_Opacity;
}
