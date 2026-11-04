// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o murk.frag.qsb murk.frag
// The MGS2 ground and its 14 drifting blobs in one opaque pass over the 1600x900 stage: each blob is a radial
// gradient ellipse laid over the ground in list order.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Seconds on the motion clock.
    float t;
    vec4 ground;
    // Per blob: g = centre x, centre y, radius x, radius y; k = light (1) or dark (0), alpha, drift rate, unused.
    vec4 g0; vec4 g1; vec4 g2; vec4 g3; vec4 g4; vec4 g5; vec4 g6;
    vec4 g7; vec4 g8; vec4 g9; vec4 g10; vec4 g11; vec4 g12; vec4 g13;
    vec4 k0; vec4 k1; vec4 k2; vec4 k3; vec4 k4; vec4 k5; vec4 k6;
    vec4 k7; vec4 k8; vec4 k9; vec4 k10; vec4 k11; vec4 k12; vec4 k13;
};

vec3 blob(vec3 under, vec2 p, vec4 g, vec4 k) {
    vec2 c = vec2(g.x + sin(t * k.z + g.y) * 60.0, g.y);
    float d = length((p - c) / g.zw);
    if (d >= 1.0) return under;
    // The gradient fades the blob's colour to transparent, interpolated premultiplied as Qt's are.
    float a = k.y * (1.0 - d);
    vec3 col = k.x > 0.5 ? vec3(0.47, 0.54, 0.494) : vec3(0.0);
    return col * a + under * (1.0 - a);
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(1600.0, 900.0);
    vec3 c = ground.rgb;
    c = blob(c, p, g0, k0);
    c = blob(c, p, g1, k1);
    c = blob(c, p, g2, k2);
    c = blob(c, p, g3, k3);
    c = blob(c, p, g4, k4);
    c = blob(c, p, g5, k5);
    c = blob(c, p, g6, k6);
    c = blob(c, p, g7, k7);
    c = blob(c, p, g8, k8);
    c = blob(c, p, g9, k9);
    c = blob(c, p, g10, k10);
    c = blob(c, p, g11, k11);
    c = blob(c, p, g12, k12);
    c = blob(c, p, g13, k13);
    fragColor = vec4(c, 1.0) * qt_Opacity;
}
