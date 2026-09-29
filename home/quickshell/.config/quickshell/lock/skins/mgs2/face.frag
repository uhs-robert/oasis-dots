// home/quickshell/.config/quickshell/lock/skins/mgs2/face.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o face.frag.qsb face.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, (qt_TexCoord0 - 0.5) / 1.15 + 0.5);
    float v = clamp((dot(c.rgb, vec3(0.3, 0.59, 0.11)) - 0.5) * 1.7 + 0.5, 0.0, 1.0);
    float band = min(3.0, floor(v * 4.0));
    vec3 col = band < 1.0 ? vec3(8.0, 3.0, 3.0) : band < 2.0 ? vec3(62.0, 8.0, 8.0) : band < 3.0 ? vec3(146.0, 20.0, 18.0) : vec3(220.0, 52.0, 40.0);
    vec2 p = qt_TexCoord0 - 0.5;
    float a = clamp((0.4167 - length(vec2(p.x / 1.15, p.y))) / 0.2917, 0.0, 1.0);
    fragColor = vec4(col / 255.0 * a, a) * qt_Opacity;
}
