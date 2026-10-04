// home/quickshell/.config/quickshell/lock/skins/goldeneye/ArmIntro.qml
import QtQuick
import QtQuick.Shapes
import QtQuick3D
import QtQuick3D.Helpers
import "../goldeneye" as GE

// The intro without footage: a low-poly sleeve, hand and watch rise into view and the camera closes on the dial until it fills the 1020 x 720 plate.
Item {
    id: root

    property real t: 0
    property real reach: 1
    property date now: new Date()
    property var panel_outline: []
    property color panel_top: "transparent"
    property color panel_bottom: "transparent"
    property bool ready: false
    readonly property real res: 0.5
    readonly property real dref: 1400
    readonly property real u: Math.max(0, Math.min(31, root.t / 0.88 * 31))
    readonly property var pose: root.pose_at(root.u)
    layer.enabled: true
    layer.effect: ShaderEffect {
        property real span_x: root.width / 1020
        property real span_y: root.height / 720
        property real reach: root.reach
        property real clip: Math.max(0, Math.min(1, root.u - 29.5))
        fragmentShader: Qt.resolvedUrl("arm.frag.qsb")
    }

    // [frame, watch x, watch y (plate fractions), case width / plate width, arm tilt, roll, yaw]
    readonly property var keys: [
        [0, 0.05, 0.95, 0.1, 60, -95, -65],
        [2, 0.09, 0.82, 0.105, 50, -90, -55],
        [4, 0.15, 0.6, 0.11, 28, -75, -35],
        [6, 0.26, 0.47, 0.115, 10, -45, -12],
        [8, 0.36, 0.44, 0.12, 3, -15, -3],
        [10, 0.47, 0.46, 0.12, 1, -4, 0],
        [14, 0.5, 0.5, 0.125, 0, 0, 0],
        [18, 0.5, 0.5, 0.15, 0, 0, 0],
        [22, 0.5, 0.5, 0.22, 0, 0, 0],
        [25, 0.5, 0.5, 0.3, 0, 0, 0],
        [27, 0.5, 0.5, 0.42, 0, 0, 0],
        [29, 0.5, 0.5, 0.62, 0, 0, 0],
        [31, 0.5, 0.5, 1, 0, 0, 0]
    ]

    function pose_at(u) {
        const k = root.keys;
        let i = 0;
        while (i < k.length - 2 && u > k[i + 1][0]) i++;
        const a = k[Math.max(0, i - 1)], b = k[i], c = k[i + 1], d = k[Math.min(k.length - 1, i + 2)];
        const f = Math.max(0, Math.min(1, (u - b[0]) / (c[0] - b[0])));
        const out = [];
        for (let j = 1; j < 7; j++) {
            const lg = j === 3;
            const p0 = lg ? Math.log(a[j]) : a[j], p1 = lg ? Math.log(b[j]) : b[j], p2 = lg ? Math.log(c[j]) : c[j], p3 = lg ? Math.log(d[j]) : d[j];
            const m1 = (p2 - p0) / Math.max(1, c[0] - a[0]) * (c[0] - b[0]), m2 = (p3 - p1) / Math.max(1, d[0] - b[0]) * (c[0] - b[0]);
            const f2 = f * f, f3 = f2 * f;
            const v = (2 * f3 - 3 * f2 + 1) * p1 + (f3 - 2 * f2 + f) * m1 + (-2 * f3 + 3 * f2) * p2 + (f3 - f2) * m2;
            out.push(lg ? Math.exp(v) : v);
        }
        const depth = root.dref / out[2];
        return { x: (out[0] * 1020 - 510) * depth / root.dref, y: -(out[1] * 720 - 360) * depth / root.dref, z: -depth, tilt: out[3], roll: out[4], yaw: out[5] };
    }

    function vec(x, y, z) {
        return Qt.vector3d(x, y, z);
    }

    function blank() {
        return { pos: [], nrm: [], uv: [], idx: [] };
    }

    function tri_normal(a, b, c) {
        return b.minus(a).crossProduct(c.minus(a)).normalized();
    }

    // A flat quad a-b-c-d, turned to face along `out`.
    function quad(m, a, b, c, d, out) {
        let n = root.tri_normal(a, b, c);
        const flip = n.dotProduct(out) < 0;
        if (flip) n = n.times(-1);
        const s = m.pos.length;
        [a, b, c, d].forEach(p => {
            m.pos.push(p);
            m.nrm.push(n);
            m.uv.push(Qt.vector2d(0, 0));
        });
        if (flip) m.idx.push(s, s + 2, s + 1, s, s + 3, s + 2);
        else m.idx.push(s, s + 1, s + 2, s, s + 2, s + 3);
    }

    // A tube along x through rings [x, cy, cz, ry, rz], smooth shaded around and flat along.
    function loft(m, rings, sides, u_scale, v_scale) {
        const s = m.pos.length;
        rings.forEach(r => {
            for (let k = 0; k <= sides; k++) {
                const a = k / sides * Math.PI * 2;
                m.pos.push(root.vec(r[0], r[1] + r[3] * Math.sin(a), r[2] + r[4] * Math.cos(a)));
                m.nrm.push(root.vec(0, Math.sin(a) / r[3], Math.cos(a) / r[4]).normalized());
                m.uv.push(Qt.vector2d(r[0] / u_scale, k / sides * v_scale));
            }
        });
        for (let i = 0; i < rings.length - 1; i++) {
            for (let k = 0; k < sides; k++) {
                const a = s + i * (sides + 1) + k, b = a + sides + 1;
                m.idx.push(a, b, b + 1, a, b + 1, a + 1);
            }
        }
    }

    function geometry(m) {
        return { positions: m.pos, normals: m.nrm, uv0s: m.uv, indexes: m.idx };
    }

    // The case's octagon on the plate, which crops its top and bottom.
    readonly property var outline: [[145, -150], [901, -150], [1020, 152], [1020, 568], [901, 870], [319, 870], [0, 617], [0, 115]].map(p => [p[0] - 510, 360 - p[1]])

    readonly property var face_mesh: {
        const m = root.blank();
        const o = root.outline;
        m.pos.push(root.vec(0, 0, 0));
        m.nrm.push(root.vec(0, 0, 1));
        m.uv.push(Qt.vector2d(0.5, 0.5));
        o.forEach(p => {
            m.pos.push(root.vec(p[0], p[1], 0));
            m.nrm.push(root.vec(0, 0, 1));
            m.uv.push(Qt.vector2d((p[0] + 510) / 1020, (p[1] + 510) / 1020));
        });
        for (let i = 0; i < o.length; i++) m.idx.push(0, 1 + (i + 1) % o.length, 1 + i);
        return root.geometry(m);
    }

    readonly property var case_mesh: {
        const m = root.blank();
        const o = root.outline;
        const rim = [[1, 0], [1.02, -60], [0.9, -200]];
        for (let i = 0; i < o.length; i++) {
            const p = o[i], q = o[(i + 1) % o.length];
            const out = root.vec(p[0] + q[0], p[1] + q[1], 0);
            for (let r = 0; r < rim.length - 1; r++) {
                const s0 = rim[r], s1 = rim[r + 1];
                root.quad(m, root.vec(q[0] * s0[0], q[1] * s0[0], s0[1]), root.vec(p[0] * s0[0], p[1] * s0[0], s0[1]), root.vec(p[0] * s1[0], p[1] * s1[0], s1[1]), root.vec(q[0] * s1[0], q[1] * s1[0], s1[1]), out);
            }
        }
        root.loft(m, [[505, 0, -90, 0.1, 0.1], [505, 0, -90, 60, 60], [640, 0, -90, 60, 60], [650, 0, -90, 0.1, 0.1]], 8, 1000, 1);
        root.loft(m, [[-470, 330, -90, 0.1, 0.1], [-470, 330, -90, 40, 40], [-550, 330, -90, 40, 40], [-560, 330, -90, 0.1, 0.1]], 6, 1000, 1);
        return root.geometry(m);
    }

    readonly property var band_mesh: {
        const m = root.blank();
        const cz = -800, ry = 760, rz = 600, w = 270;
        for (let sgn = -1; sgn <= 1; sgn += 2) {
            const path = [[sgn * 470, -60], [sgn * 560, -150]];
            for (let a = 50; a <= 170; a += 12) {
                const r = a * Math.PI / 180;
                path.push([sgn * (ry + 40) * Math.sin(r), cz + (rz + 40) * Math.cos(r)]);
            }
            for (let i = 0; i < path.length - 1; i++) {
                const p = path[i], q = path[i + 1];
                const g = i === 0 ? 0 : 0.07;
                const a = [p[0] + (q[0] - p[0]) * g, p[1] + (q[1] - p[1]) * g], b = [q[0] - (q[0] - p[0]) * 0.07, q[1] - (q[1] - p[1]) * 0.07];
                const mid = root.vec(0, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - cz);
                const inward = mid.normalized().times(-46);
                const top = [root.vec(-w, a[0], a[1]), root.vec(w, a[0], a[1]), root.vec(w, b[0], b[1]), root.vec(-w, b[0], b[1])];
                const low = top.map(v => v.plus(inward));
                root.quad(m, top[0], top[1], top[2], top[3], mid);
                root.quad(m, top[1], low[1], low[2], top[2], root.vec(1, 0, 0));
                root.quad(m, low[0], top[0], top[3], low[3], root.vec(-1, 0, 0));
                root.quad(m, top[3], top[2], low[2], low[3], root.vec(0, b[0] - a[0], b[1] - a[1]));
                root.quad(m, low[0], low[1], top[1], top[0], root.vec(0, a[0] - b[0], a[1] - b[1]));
            }
        }
        return root.geometry(m);
    }

    readonly property var skin_mesh: {
        const m = root.blank();
        root.loft(m, [
            [-900, 0, -800, 700, 560], [0, 0, -800, 700, 600], [560, 0, -800, 720, 600], [1100, 40, -820, 820, 620],
            [1800, 110, -860, 1060, 640], [2500, 150, -900, 1180, 640], [3100, 150, -960, 1180, 620], [3450, 130, -1060, 1120, 540],
            [3560, 120, -1140, 860, 380], [3580, 120, -1160, 1, 1]
        ], 8, 900, 2);
        [-650, -215, 215, 650].forEach((y, i) => {
            const c = 150 + y, l = i === 0 || i === 3 ? 0.9 : 1;
            root.loft(m, [[3200, c, -900, 270, 300], [3200 + 550 * l, c, -980, 260, 290], [3200 + 900 * l, c - 10, -1200, 240, 260], [3200 + 1020 * l, c - 20, -1500, 210, 230], [3200 + 1030 * l, c - 20, -1600, 1, 1]], 6, 900, 2);
        });
        return root.geometry(m);
    }

    readonly property var sleeve_mesh: {
        const m = root.blank();
        root.loft(m, [[-14000, 0, -1300, 1300, 1150], [-3000, 20, -1260, 1260, 1100], [-650, 0, -1250, 1230, 1060], [-560, 0, -1250, 1230, 1060], [-560, 0, -1250, 1000, 860], [-540, 0, -1250, 1, 1]], 8, 900, 3);
        return root.geometry(m);
    }

    function pixels(w, h, fn) {
        const buf = new ArrayBuffer(w * h * 4);
        const px = new Uint8Array(buf);
        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                const c = fn(x, y);
                const i = (y * w + x) * 4;
                px[i] = c[0];
                px[i + 1] = c[1];
                px[i + 2] = c[2];
                px[i + 3] = 255;
            }
        }
        return buf;
    }

    function noise(x, y) {
        const s = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
        return s - Math.floor(s);
    }

    View3D {
        id: view
        width: root.width * root.res
        height: root.height * root.res
        scale: 1 / root.res
        transformOrigin: Item.TopLeft
        renderMode: View3D.Offscreen

        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            id: camera
            fieldOfView: 2 * Math.atan(root.height / 2 / root.dref) * 180 / Math.PI
            clipNear: 50
            clipFar: 60000
        }

        DirectionalLight {
            eulerRotation: Qt.vector3d(-38, 28, 0)
            brightness: 1.05
            ambientColor: Qt.rgba(0.26, 0.26, 0.28, 1)
        }

        Node {
            position: Qt.vector3d(root.pose.x, root.pose.y, root.pose.z)
            eulerRotation.z: root.pose.tilt

            Node {
                eulerRotation.y: root.pose.yaw

                Node {
                    eulerRotation.x: root.pose.roll

                    Model {
                        geometry: ProceduralMesh {
                            positions: root.sleeve_mesh.positions
                            normals: root.sleeve_mesh.normals
                            uv0s: root.sleeve_mesh.uv0s
                            indexes: root.sleeve_mesh.indexes
                        }
                        materials: DefaultMaterial {
                            diffuseMap: Texture {
                                textureData: ProceduralTextureData {
                                    width: 32
                                    height: 32
                                    format: TextureData.RGBA8
                                    textureData: root.pixels(32, 32, (x, y) => {
                                        const line = (x % 16 < 2 ? 1 : 0) + (y % 16 < 2 ? 1 : 0) + (x % 16 === 8 ? 0.5 : 0) + (y % 16 === 8 ? 0.5 : 0);
                                        const n = root.noise(x, y) * 8;
                                        return [24 + line * 6 + n, 29 + line * 7 + n, 44 + line * 10 + n];
                                    })
                                }
                            }
                        }
                    }

                    Model {
                        geometry: ProceduralMesh {
                            positions: root.skin_mesh.positions
                            normals: root.skin_mesh.normals
                            uv0s: root.skin_mesh.uv0s
                            indexes: root.skin_mesh.indexes
                        }
                        materials: DefaultMaterial {
                            diffuseMap: Texture {
                                textureData: ProceduralTextureData {
                                    width: 16
                                    height: 16
                                    format: TextureData.RGBA8
                                    textureData: root.pixels(16, 16, (x, y) => {
                                        const n = (root.noise(x + 3, y) - 0.5) * 18;
                                        return [164 + n, 118 + n, 84 + n * 0.8];
                                    })
                                }
                            }
                        }
                    }

                    Model {
                        geometry: ProceduralMesh {
                            positions: root.band_mesh.positions
                            normals: root.band_mesh.normals
                            uv0s: root.band_mesh.uv0s
                            indexes: root.band_mesh.indexes
                        }
                        materials: DefaultMaterial {
                            diffuseColor: "#b4b6ba"
                            specularAmount: 0.6
                            specularRoughness: 0.3
                            cullMode: Material.NoCulling
                        }
                    }

                    Model {
                        geometry: ProceduralMesh {
                            positions: root.case_mesh.positions
                            normals: root.case_mesh.normals
                            uv0s: root.case_mesh.uv0s
                            indexes: root.case_mesh.indexes
                        }
                        materials: DefaultMaterial {
                            diffuseColor: "#6c6e73"
                            specularAmount: 0.7
                            specularRoughness: 0.25
                            cullMode: Material.NoCulling
                        }
                    }

                    Model {
                        geometry: ProceduralMesh {
                            positions: root.face_mesh.positions
                            normals: root.face_mesh.normals
                            uv0s: root.face_mesh.uv0s
                            indexes: root.face_mesh.indexes
                        }
                        materials: DefaultMaterial {
                            lighting: DefaultMaterial.NoLighting
                            cullMode: Material.NoCulling
                            diffuseMap: Texture {
                                sourceItem: root.dial
                            }
                        }
                    }
                }
            }
        }
    }

    // Held by a property, not parented, so Qt Quick 3D renders it offscreen for the face texture.
    property Item dial: Item {
        width: 1020
        height: 1020

        ShaderEffect {
            property real soft: 1.5
            property real rows: 1020
            property real minutes: 1
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("plate.frag.qsb")
        }

        Item {
            y: 150
            width: 1020
            height: 720

            Shape {
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0
                        y1: 118
                        x2: 0
                        y2: 603
                        GradientStop { position: 0; color: root.panel_top }
                        GradientStop { position: 1; color: root.panel_bottom }
                    }
                    PathPolyline { path: root.panel_outline }
                }
            }

            GE.WatchHands {
                now: root.now
            }
        }
    }

    FrameAnimation {
        running: !root.ready
        onTriggered: if (currentFrame >= 3) root.ready = true
    }
}
