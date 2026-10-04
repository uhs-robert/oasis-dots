// home/quickshell/.config/quickshell/lock/skins/goldeneye/plate.frag
// Rebuild: /usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o plate.frag.qsb plate.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float soft;
    float rows;
    float minutes;
};

const vec2 C = vec2(510.0, 360.0);

vec2 edge(vec2 acc, vec2 p, vec2 vi, vec2 vj) {
    vec2 e = vj - vi;
    vec2 w = p - vi;
    vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-4), 0.0, 1.0);
    bool c1 = p.y >= vi.y;
    bool c2 = p.y < vj.y;
    bool c3 = e.x * w.y > e.y * w.x;
    float flip = (c1 && c2 && c3) || (!c1 && !c2 && !c3) ? -1.0 : 1.0;
    return vec2(min(acc.x, dot(b, b)), acc.y * flip);
}

float sd_poly(vec2 p, vec2 v0, vec2 v1, vec2 v2, vec2 v3, vec2 v4, vec2 v5, vec2 v6, vec2 v7) {
    vec2 acc = vec2(dot(p - v0, p - v0), 1.0);
    acc = edge(acc, p, v0, v7);
    acc = edge(acc, p, v1, v0);
    acc = edge(acc, p, v2, v1);
    acc = edge(acc, p, v3, v2);
    acc = edge(acc, p, v4, v3);
    acc = edge(acc, p, v5, v4);
    acc = edge(acc, p, v6, v5);
    acc = edge(acc, p, v7, v6);
    return acc.y * sqrt(acc.x);
}

float cover(float d) {
    return clamp(0.5 - d / soft, 0.0, 1.0);
}

float hash(vec2 q) {
    return fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
}

float blotch(vec2 q) {
    vec2 i = floor(q);
    vec2 t = q - i;
    float a = mix(hash(i), hash(i + vec2(1.0, 0.0)), t.x);
    float b = mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), t.x);
    return mix(a, b, t.y);
}

float sd_box(vec2 p, vec2 a, vec2 b) {
    vec2 c = (a + b) * 0.5;
    vec2 q = abs(p - c) - (b - a) * 0.5;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float sd_sector(vec2 p, float a0, float a1, float r0, float r1) {
    vec2 d = p - C;
    float r = length(d);
    float mid = radians((a0 + a1) * 0.5);
    float half_w = radians((a1 - a0) * 0.5);
    float da = atan(d.x * sin(mid) - d.y * cos(mid), d.x * cos(mid) + d.y * sin(mid));
    return max(max(r - r1, r0 - r), (abs(da) - half_w) * r);
}

float sd_ray(vec2 p, float a, float r0, float r1, float w) {
    vec2 dir = vec2(cos(radians(a)), sin(radians(a)));
    vec2 d = p - C;
    float along = dot(d, dir);
    float across = abs(d.x * dir.y - d.y * dir.x);
    return max(across - w, max(r0 - along, along - r1));
}

vec3 over(vec3 base, vec3 col, float a) {
    return mix(base, col, a);
}

vec3 segment(vec3 col, vec2 p, float mid, float hw, vec3 warm, vec3 cold, float shade) {
    col = over(col, warm * shade, cover(sd_sector(p, mid - hw, mid + hw, 360.0, 431.5)));
    return over(col, cold * shade, cover(sd_sector(p, 180.0 - mid - hw, 180.0 - mid + hw, 360.0, 431.5)));
}

vec3 tick(vec3 col, vec2 p, float a) {
    return over(col, vec3(0.97), cover(sd_ray(p, a, 445.0, 510.0, 7.0)));
}

vec3 bar(vec3 base, vec2 p, vec2 a, vec2 b) {
    float u = (p.x - a.x) / (b.x - a.x);
    float v = (p.y - a.y) / (b.y - a.y);
    vec3 col = vec3(0.95, 0.95, 0.92);
    col = mix(col, vec3(0.97, 0.96, 0.84), smoothstep(0.25, 0.5, u) * (1.0 - smoothstep(0.55, 0.8, u)));
    col *= 1.0 - 0.32 * exp(-pow((u - 0.28) / 0.07, 2.0)) * smoothstep(0.05, 0.25, v);
    col *= 1.0 - 0.18 * smoothstep(0.75, 1.0, v) * (1.0 - smoothstep(0.2, 0.5, u));
    return over(base, col, cover(sd_box(p, a, b)));
}

vec3 stud(vec3 base, vec2 p, vec2 c) {
    vec2 d = (p - c) / 19.5;
    float r2 = dot(d, d);
    vec3 n = vec3(d, sqrt(max(0.0, 1.0 - r2)));
    float lit = dot(n, normalize(vec3(0.25, -0.55, 0.8)));
    vec3 col = vec3(1.0, 0.99, 0.93) * clamp(0.18 + 1.25 * lit, 0.0, 1.0);
    return over(base, col, cover((sqrt(r2) - 1.0) * 19.5));
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(1020.0, rows) - vec2(0.0, (rows - 720.0) * 0.5);
    vec2 f = vec2(p.x, min(p.y, 720.0 - p.y));

    float grain = blotch(p / 6.0) - 0.5;
    vec3 col = vec3(0.0);

    float left_a = sd_poly(f, vec2(63.0, 0.0), vec2(135.0, 0.0), vec2(60.0, 107.0), vec2(0.0, 240.0), vec2(0.0, 240.0), vec2(0.0, 240.0), vec2(0.0, 115.0), vec2(0.0, 115.0));
    col = over(col, vec3(0.112 + 0.012 * smoothstep(40.0, 110.0, f.y) * (1.0 - smoothstep(110.0, 200.0, f.y))) + grain * 0.012, cover(left_a));
    float left_b = sd_poly(f, vec2(0.0, 238.0), vec2(56.0, 238.0), vec2(9.0, 362.0), vec2(0.0, 362.0), vec2(0.0, 362.0), vec2(0.0, 362.0), vec2(0.0, 362.0), vec2(0.0, 362.0));
    col = over(col, vec3(0.04 + 0.018 * smoothstep(238.0, 320.0, f.y)) + grain * 0.01, cover(left_b));
    col = over(col, vec3(0.105), cover(sd_box(f, vec2(1.0, 236.0), vec2(9.0, 250.0))) * (1.0 - smoothstep(236.0, 250.0, f.y)));

    float right_b = sd_poly(p, vec2(1020.0, 362.0), vec2(1012.0, 362.0), vec2(950.0, 522.0), vec2(1020.0, 522.0), vec2(1020.0, 522.0), vec2(1020.0, 522.0), vec2(1020.0, 522.0), vec2(1020.0, 522.0));
    col = over(col, vec3(0.025 + 0.11 * smoothstep(380.0, 520.0, p.y)) + grain * 0.01, cover(right_b));
    float right_a = sd_poly(f, vec2(960.0, 0.0), vec2(1020.0, 152.0), vec2(1020.0, 300.0), vec2(960.0, 107.0), vec2(882.0, 0.0), vec2(882.0, 0.0), vec2(882.0, 0.0), vec2(882.0, 0.0));
    float shine = mix(0.34, 0.42, smoothstep(0.0, 90.0, f.y)) * (1.0 - 0.9 * smoothstep(210.0, 300.0, f.y));
    shine *= 1.0 + 0.08 * smoothstep(0.0, 40.0, p.x - 960.0 - f.y * 0.4);
    col = over(col, vec3(shine) + grain * 0.035, cover(right_a));

    float off_plate = step(p.y, 0.0) + step(720.0, p.y);
    float metal = mix(0.112, 0.36, smoothstep(300.0, 720.0, p.x)) + grain * 0.02;
    col = mix(col, vec3(metal), off_plate * cover(516.0 - length(p - C)));
    col *= cover(sd_poly(p, vec2(145.0, -150.0), vec2(901.0, -150.0), vec2(1020.0, 152.0), vec2(1020.0, 568.0), vec2(901.0, 870.0), vec2(319.0, 870.0), vec2(0.0, 617.0), vec2(0.0, 115.0)));

    float shade = 1.0 + grain * 0.05;
    col = segment(col, p, 225.5, 7.6, vec3(0.969, 0.114, 0.039), vec3(0.031, 0.039, 0.157), shade);
    col = segment(col, p, 205.4, 7.6, vec3(0.969, 0.231, 0.059), vec3(0.051, 0.055, 0.161), shade);
    col = segment(col, p, 185.4, 7.6, vec3(0.969, 0.388, 0.094), vec3(0.071, 0.078, 0.161), shade);
    col = segment(col, p, 170.4, 2.55, vec3(0.961, 0.514, 0.118), vec3(0.082, 0.094, 0.153), shade);
    col = segment(col, p, 160.4, 2.55, vec3(0.961, 0.6, 0.133), vec3(0.078, 0.102, 0.149), shade);
    col = segment(col, p, 150.4, 2.55, vec3(0.961, 0.682, 0.153), vec3(0.098, 0.114, 0.157), shade);
    col = segment(col, p, 140.4, 2.55, vec3(0.961, 0.757, 0.169), vec3(0.102, 0.125, 0.157), shade);
    col = segment(col, p, 130.4, 2.55, vec3(0.961, 0.827, 0.184), vec3(0.102, 0.129, 0.153), shade);

    if (minutes > 0.0) {
        vec2 d = p - C;
        float a = degrees(atan(d.y, d.x)) / 6.0;
        float r = length(d);
        float gap = abs(a - floor(a + 0.5)) * 6.0 * 0.01745 * r;
        float tick = max(gap - 3.0, max(437.0 - r, r - 468.0));
        col = over(col, vec3(0.93), cover(tick) * minutes);
    }

    col = tick(col, p, 0.0);
    col = tick(col, p, 30.0);
    col = tick(col, p, 90.0);
    col = tick(col, p, 150.0);
    col = tick(col, p, 180.0);
    col = tick(col, p, 210.0);
    col = tick(col, p, 270.0);
    col = tick(col, p, 330.0);

    col = over(col, vec3(0.97), cover(sd_box(p, vec2(166.0, 366.0), vec2(186.0, 373.0))));
    col = over(col, vec3(0.92), cover(sd_box(p, vec2(163.0, 344.0), vec2(188.0, 370.0))));
    col = over(col, vec3(0.97), cover(sd_box(p, vec2(834.0, 366.0), vec2(854.0, 373.0))));
    col = over(col, vec3(0.92), cover(sd_box(p, vec2(832.0, 344.0), vec2(857.0, 370.0))));
    col = bar(col, p, vec2(479.0, 22.0), vec2(503.0, 102.0));
    col = bar(col, p, vec2(516.0, 22.0), vec2(545.0, 102.0));
    col = bar(col, p, vec2(498.0, 621.0), vec2(522.0, 699.0));

    col = stud(col, p, vec2(350.0, 85.5));
    col = stud(col, p, vec2(669.0, 85.5));
    col = stud(col, p, vec2(231.0, 201.0));
    col = stud(col, p, vec2(789.0, 201.0));
    col = stud(col, p, vec2(231.0, 521.0));
    col = stud(col, p, vec2(789.0, 521.0));
    col = stud(col, p, vec2(351.0, 636.5));
    col = stud(col, p, vec2(669.0, 638.0));

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
