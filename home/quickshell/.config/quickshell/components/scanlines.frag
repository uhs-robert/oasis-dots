// home/quickshell/.config/quickshell/components/scanlines.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o scanlines.frag.qsb scanlines.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float height;
    float period;
    vec4 color;
};

void main() {
    // Rounded to 8 bits like a Rectangle's vertex colour, so faint lines blend identically.
    vec4 col = floor(color * 255.0 + 0.5) / 255.0;
    // Snapped so a pixel centre on a line edge falls the way the rasterizer took it for a Rectangle.
    float m = mod(floor(qt_TexCoord0.y * height * 256.0 + 0.5) / 256.0, period);
    fragColor = m > 0.0 && m <= 1.0 ? col * qt_Opacity : vec4(0.0);
}
