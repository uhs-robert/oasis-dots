// home/quickshell/.config/quickshell/lock/skins/ff7/lifestream.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o lifestream.frag.qsb lifestream.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;
    vec2 res;
    vec4 green;
    vec4 teal;
    vec4 white;
};

vec3 acc_col = vec3(0.0);
float acc_a = 0.0;

void add(vec3 col, float a) {
    acc_col += col * a;
    acc_a += a;
}

float hash(float n) {
    n = fract(n * 0.1031);
    n *= n + 33.33;
    n *= n + n;
    return fract(n);
}

float stroke(float dist, float width, float aa) {
    return clamp((width * 0.5 - dist) / aa + 0.5, 0.0, 1.0);
}

float dot_at(vec2 p, vec2 c, float r, float aa) {
    return clamp((r - length(p - c)) / aa + 0.5, 0.0, 1.0);
}

void band(vec2 p, float aa, float fade, float y0, float amp, float kk, float w, float spread, float twist, float tilt, float n, float ph, float seed, float white_bits, float teal_bits) {
    float x = p.x;
    float a1 = kk * x - w * t + ph;
    float a2 = kk * 2.3 * x + w * 0.6 * t;
    float centre = y0 + (x - 800.0) * tilt + amp * sin(a1) + amp * 0.35 * sin(a2);
    float dc = tilt + amp * kk * cos(a1) + amp * 0.35 * kk * 2.3 * cos(a2);
    float ap = twist * x - w * 1.4 * t + ph * 2.0;
    float pinch = cos(ap);
    float dp = -twist * sin(ap);
    float dy = p.y - centre;

    float dist = abs(dy) / sqrt(1.0 + dc * dc);
    add(green.rgb, fade * (0.07 * stroke(dist, spread * 1.6, aa) + 0.1 * stroke(dist, spread * 0.6, aa)));

    if (abs(dy) < spread * abs(pinch) + 18.0 + 2.0 * aa) {
        float aw = x * 0.011 + t * 0.7;
        float sa = sin(aw);
        float ca = cos(aw);
        for (float i = 0.0; i < 14.0; i += 1.0) {
            if (i >= n) break;
            float o = (i / (n - 1.0) - 0.5) * 2.0;
            float h = seed + i * 4.0;
            float wob = 3.0 + hash(h + 1.0) * 8.0;
            float f = hash(h + 2.0) * 6.0;
            float bit = exp2(i);
            bool is_white = mod(floor(white_bits / bit), 2.0) > 0.5;
            bool is_teal = mod(floor(teal_bits / bit), 2.0) > 0.5;
            float lit = is_white ? 0.85 + hash(h + 3.0) * 0.15 : is_teal ? 0.55 + hash(h + 3.0) * 0.3 : 0.35 + hash(h + 3.0) * 0.2;
            float sf = sin(f);
            float cf = cos(f);
            float ys = centre + spread * o * pinch + wob * (sa * cf + ca * sf);
            float ds = dc + spread * o * dp + wob * 0.011 * (ca * cf - sa * sf);
            float d = abs(p.y - ys) / sqrt(1.0 + ds * ds);
            vec3 col = is_white ? white.rgb : is_teal ? teal.rgb : green.rgb;
            add(col, fade * lit * (0.18 * (1.0 - smoothstep(1.2, 3.8, d)) + 0.75 * stroke(d, 1.3, aa)));
        }
    }

    if (abs(dy) < spread * 1.5 + 12.0) {
        float dim_cov = 0.0;
        float bright_cov = 0.0;
        for (float i = 0.0; i < 55.0; i += 1.0) {
            float h = seed + 100.0 + i * 5.0;
            float sx = mod(hash(h + 1.0) * 1760.0 + (40.0 + hash(h + 2.0) * 70.0) * t, 1760.0) - 80.0;
            if (abs(x - sx) > 3.0) continue;
            float so = (hash(h + 3.0) * 2.0 - 1.0) * 1.5;
            float b1 = kk * sx - w * t + ph;
            float b2 = kk * 2.3 * sx + w * 0.6 * t;
            float sy = y0 + (sx - 800.0) * tilt + amp * sin(b1) + amp * 0.35 * sin(b2) + spread * so * cos(twist * sx - w * 1.4 * t + ph * 2.0);
            float r = (0.8 + hash(h + 4.0) * 1.8) * (0.6 + 0.4 * sin(t * 2.5 + hash(h + 5.0) * 6.0));
            float cov = dot_at(p, vec2(sx, sy), r, aa);
            if (mod(i, 4.0) < 0.5) bright_cov = max(bright_cov, cov);
            else dim_cov = max(dim_cov, cov);
        }
        add(green.rgb, 0.7 * dim_cov);
        add(white.rgb, 0.9 * bright_cov);
    }
}

void main() {
    float k = max(res.x / 1600.0, res.y / 900.0);
    vec2 p = (qt_TexCoord0 * res - (res - vec2(1600.0, 900.0) * k) * 0.5) / k;
    float aa = 1.0 / k;
    float u = qt_TexCoord0.x;
    float fade = clamp(u / 0.12, 0.0, 1.0) * clamp((1.0 - u) / 0.12, 0.0, 1.0);

    for (float i = 0.0; i < 70.0; i += 1.0) {
        float h = 900.0 + i * 7.0;
        float my = hash(h + 2.0) * 900.0;
        float f = 0.2 + hash(h + 5.0) * 0.5;
        float y = mod(my - (10.0 + hash(h + 3.0) * 26.0) * t, 900.0);
        if (abs(p.y - y) > 4.0) continue;
        float mx = hash(h + 1.0) * 1600.0;
        float x = mx + sin(t * f + mx) * (10.0 + hash(h + 4.0) * 40.0);
        float cov = dot_at(p, vec2(x, y), 0.8 + hash(h + 6.0) * 1.8, aa);
        add(green.rgb, (0.25 + 0.25 * sin(t * f * 3.0 + my)) * cov);
    }

    band(p, aa, fade, 300.0, 70.0, 0.0042, 0.35, 46.0, 0.0031, -0.06, 11.0, 0.4, 0.0, 1600.0, 414.0);
    band(p, aa, fade, 520.0, 105.0, 0.0033, 0.28, 62.0, 0.0026, 0.05, 14.0, 2.1, 400.0, 0.0, 2017.0);
    band(p, aa, fade, 720.0, 60.0, 0.0048, 0.4, 38.0, 0.0036, -0.03, 9.0, 4.2, 800.0, 12.0, 66.0);

    fragColor = vec4(min(acc_col, vec3(1.0)), min(acc_a, 1.0)) * qt_Opacity;
}
