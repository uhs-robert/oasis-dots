// home/quickshell/.config/quickshell/components/oasis/OasisDay.qml
import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../theme"
import "../../services"

// One Daily column: icon, a hi/lo range pill, rain chance and the weekday on a horizon; the selected day rises in sand.
// On the wind, UV and sunshine subs the pill becomes a dune whose height is the day's value.
Item {
    id: root

    property var day: null
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1
    // 0 temp range, 1 wind, 2 UV, 3 sunshine.
    property int sub: 0
    property real wind_max: 1
    // The horizon under the names fades in at the window's first column and out at its last.
    property bool first: false
    property bool last: false
    // Half the gap to the neighbouring columns, so the horizon runs unbroken.
    property real bleed: 2

    readonly property color sand: Theme.theme_secondary
    readonly property color hair: Qt.alpha(Theme.theme_primary, 0.3)
    // The icon art fills about half its box, so the box runs large and gives back its empty margin.
    readonly property int icon_size: Math.max(24, Math.min(48, root.width - 6))
    readonly property int icon_margin: Math.round(root.icon_size * 0.18)
    readonly property int name_h: name.implicitHeight + 11
    readonly property int pop_h: pop.implicitHeight + 4
    readonly property real track_top: icon.y + root.icon_size - root.icon_margin + 4 + hi.implicitHeight + 4
    readonly property real track_bottom: root.height - root.name_h - root.pop_h - lo.implicitHeight - 8
    readonly property real span: Math.max(1, root.scale_max - root.scale_min)

    readonly property bool dune_sub: root.sub > 0 && !!root.day
    readonly property real dune_top: root.track_top - 4
    readonly property real dune_base: root.height - root.name_h - root.pop_h - 22
    readonly property real level: {
        if (!root.day) return 0;
        const v = root.sub === 1 ? root.day.wind_speed_max / root.wind_max : root.sub === 2 ? root.day.uv_max / 12 : root.day.sunshine_hours / 14;
        return Math.max(0, Math.min(1, v));
    }
    readonly property color dune_color: root.sub === 2 && root.day ? WeatherState.uv_color(root.day.uv_max) : root.sand
    readonly property string dune_value: {
        if (!root.day) return "";
        return root.sub === 1 ? String(Math.round(root.day.wind_speed_max)) : root.sub === 2 ? root.day.uv_max.toFixed(1) : root.day.sunshine_hours.toFixed(1) + "h";
    }
    readonly property string dune_detail: {
        if (!root.day) return "";
        return root.sub === 1 ? WeatherState.compass_label(root.day.wind_dir) + " g" + Math.round(root.day.wind_gusts_max) : root.sub === 2 ? WeatherState.uv_band(root.day.uv_max).label : "";
    }
    // Wind from the east drifts sand west.
    readonly property int downwind: root.day && Math.sin(root.day.wind_dir * Math.PI / 180) > 0 ? -1 : 1

    onLevelChanged: dune.requestPaint()
    onSubChanged: dune.requestPaint()
    onSelectedChanged: dune.requestPaint()
    onDayChanged: dune.requestPaint()

    function y_for(t) {
        return root.track_top + (root.scale_max - t) / root.span * Math.max(1, root.track_bottom - root.track_top);
    }

    Shape {
        visible: root.selected
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.width / 2
                centerY: root.height * 0.94
                focalX: centerX
                focalY: centerY
                centerRadius: Math.max(root.width * 0.62, 1)
                focalRadius: 0
                GradientStop { position: 0; color: Qt.alpha(root.sand, 0.14) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { width: root.width; height: root.height }
        }
    }

    Image {
        id: icon
        anchors.horizontalCenter: parent.horizontalCenter
        y: 6 - root.icon_margin
        width: root.icon_size
        height: root.icon_size
        readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
        sourceSize.width: Math.ceil(96 * dpr)
        sourceSize.height: Math.ceil(96 * dpr)
        source: root.day ? WeatherState.icon_source(root.day.code, true) : ""
        smooth: true
        opacity: root.selected ? 1 : 0.85
    }

    readonly property real top_y: root.day ? root.y_for(root.day.max) : root.track_top
    readonly property real bottom_y: root.day ? Math.max(root.top_y + 6, root.y_for(root.day.min)) : root.track_top + 6

    Text {
        id: hi
        visible: root.sub === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.top_y - implicitHeight - 4
        text: root.day ? Math.round(root.day.max) + "°" : ""
        color: root.selected ? Theme.fg_strong : Theme.fg_core
        font.family: Style.number_font
        font.pixelSize: Style.fs(-2)
        font.weight: root.selected ? Font.Medium : Font.Normal
        font.features: { "tnum": 1 }
    }

    Rectangle {
        visible: root.selected && root.sub === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.top_y - 3
        width: 14
        height: root.bottom_y - root.top_y + 6
        radius: width / 2
        color: Theme.bg_mantle
        border.width: 1
        border.color: Qt.alpha(root.sand, 0.7)
    }

    Rectangle {
        visible: root.sub === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.top_y
        width: root.selected ? 8 : 6
        height: root.bottom_y - root.top_y
        radius: width / 2
        opacity: root.selected ? 1 : 0.8
        gradient: Gradient {
            GradientStop { position: 0; color: root.selected ? root.sand : Qt.tint(Theme.theme_primary_light, Qt.alpha(root.sand, 0.5)) }
            GradientStop { position: 1; color: root.selected ? Theme.theme_primary : Theme.theme_primary_strong }
        }
    }

    Text {
        id: lo
        visible: root.sub === 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bottom_y + 4
        text: root.day ? Math.round(root.day.min) + "°" : ""
        color: Theme.fg_dim
        font.family: Style.number_font
        font.pixelSize: Style.fs(-3)
        font.features: { "tnum": 1 }
    }

    Canvas {
        id: dune
        visible: root.dune_sub
        x: 0
        y: root.dune_top
        width: root.width
        height: Math.max(1, root.dune_base - root.dune_top + 2)
        opacity: root.selected ? 1 : 0.8

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: Style
            function onPalChanged() { dune.requestPaint(); }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.dune_sub) return;
            const w = width, h = height;
            const floor_y = h - 2;
            // The top 34px stay free for the value above the dune and a sun's glare on its crest.
            const rise = Math.max(5, root.level * (h - 34));
            const crest_y = floor_y - rise;
            const dir = root.sub === 1 ? root.downwind : 1;
            const left = w * 0.06, right = w * 0.94;
            // The windward face is long and gentle, the lee face short and steep.
            const crest_x = w / 2 - dir * w * (root.sub === 1 ? 0.12 : 0);
            const color = root.dune_color;

            const body = ctx.createLinearGradient(0, crest_y, 0, floor_y);
            body.addColorStop(0, Qt.alpha(Qt.tint(color, Qt.alpha(Theme.fg_strong, root.selected ? 0.25 : 0.1)), root.selected ? 0.95 : 0.8));
            body.addColorStop(1, Qt.alpha(color, 0.25));

            ctx.beginPath();
            ctx.moveTo(left, floor_y);
            ctx.bezierCurveTo(left + (crest_x - left) * 0.55, floor_y, crest_x - (crest_x - left) * 0.45, crest_y, crest_x, crest_y);
            ctx.bezierCurveTo(crest_x + (right - crest_x) * 0.45, crest_y, crest_x + (right - crest_x) * 0.55, floor_y, right, floor_y);
            ctx.closePath();
            ctx.fillStyle = body;
            ctx.fill();

            ctx.lineCap = "round";
            ctx.lineWidth = 1;
            ctx.strokeStyle = Qt.alpha(Theme.fg_strong, root.selected ? 0.5 : 0.28);
            ctx.beginPath();
            ctx.moveTo(left, floor_y);
            ctx.bezierCurveTo(left + (crest_x - left) * 0.55, floor_y, crest_x - (crest_x - left) * 0.45, crest_y, crest_x, crest_y);
            ctx.bezierCurveTo(crest_x + (right - crest_x) * 0.45, crest_y, crest_x + (right - crest_x) * 0.55, floor_y, right, floor_y);
            ctx.stroke();

            if (root.sub === 1) {
                // Spindrift streaks lifting off the crest and trailing downwind.
                const gust = Math.max(root.level, Math.min(1, root.day.wind_gusts_max / root.wind_max));
                const len = 6 + gust * w * 0.4;
                for (let k = 0; k < 3; k++) {
                    const y = crest_y + 2 + k * 6;
                    const x0 = crest_x + dir * (k * 4);
                    const trail = ctx.createLinearGradient(x0, 0, x0 + dir * len, 0);
                    trail.addColorStop(0, Qt.alpha(Theme.theme_primary_light, 0.8));
                    trail.addColorStop(1, Qt.alpha(Theme.theme_primary_light, 0));
                    ctx.strokeStyle = trail;
                    ctx.lineWidth = 1.4;
                    ctx.beginPath();
                    ctx.moveTo(x0, y);
                    ctx.lineTo(x0 + dir * len * (1 - k * 0.2), y);
                    ctx.stroke();
                }
            } else if (root.sub === 2) {
                // Heat rising off the crest; hotter days shimmer higher.
                const lift = 8 + root.level * 16;
                for (let k = 0; k < 3; k++) {
                    ctx.strokeStyle = Qt.alpha(color, 0.55 - k * 0.15);
                    ctx.lineWidth = 1.2;
                    ctx.beginPath();
                    const y0 = crest_y - 5 - k * lift / 3;
                    for (let x = -w * 0.2; x <= w * 0.2; x += 2) {
                        const y = y0 + 1.8 * Math.sin(x / 3.5 + k * 1.3);
                        if (x === -w * 0.2) ctx.moveTo(crest_x + x, y); else ctx.lineTo(crest_x + x, y);
                    }
                    ctx.stroke();
                }
            } else {
                // Glare: the sun on the crest, bigger and brighter the more hours it shone.
                const glare = 8 + root.level * 18;
                const halo = ctx.createRadialGradient(crest_x, crest_y, 1, crest_x, crest_y, glare);
                halo.addColorStop(0, Qt.alpha(Theme.theme_secondary, 0.85));
                halo.addColorStop(1, Qt.alpha(Theme.theme_secondary, 0));
                ctx.fillStyle = halo;
                ctx.fillRect(crest_x - glare, crest_y - glare, glare * 2, glare * 2);
                ctx.fillStyle = Qt.tint(Theme.theme_secondary, Qt.alpha(Theme.fg_strong, 0.6));
                ctx.beginPath();
                ctx.arc(crest_x, crest_y, 2 + root.level * 3.5, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }

    Text {
        visible: root.dune_sub
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.dune_top - 4
        text: root.dune_value
        color: root.selected ? Theme.fg_strong : Theme.fg_core
        font.family: Style.number_font
        font.pixelSize: Style.fs(-2)
        font.weight: root.selected ? Font.Medium : Font.Normal
        font.features: { "tnum": 1 }
    }

    Text {
        visible: root.dune_sub
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, root.width)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        y: root.dune_base + 3
        text: root.dune_detail
        color: Theme.fg_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-4)
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - root.name_h - root.pop_h
        spacing: 4

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 2.5
            topRightRadius: 0
            rotation: -45
            color: Qt.alpha(Theme.info, 0.8)
        }

        Text {
            id: pop
            text: root.day ? root.day.pop + "%" : ""
            color: Qt.tint(Theme.fg_core, Qt.alpha(Theme.info, 0.75))
            font.family: Style.number_font
            font.pixelSize: Style.fs(-3)
            font.features: { "tnum": 1 }
        }
    }

    Rectangle {
        x: -root.bleed
        y: root.height - root.name_h + 2
        width: root.width + root.bleed * 2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.first ? "transparent" : root.hair }
            GradientStop { position: 1; color: root.last ? "transparent" : root.hair }
        }
    }

    Rectangle {
        visible: root.selected
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - root.name_h - 1
        width: 11
        height: 11
        radius: 5.5
        color: Theme.bg_mantle

        Rectangle {
            anchors.centerIn: parent
            width: 7
            height: 7
            radius: 3.5
            color: root.sand
        }
    }

    Text {
        id: name
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: root.day ? root.day.weekday : ""
        color: root.selected ? root.sand : Theme.fg_dim
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        font.weight: root.selected ? Font.DemiBold : Font.Medium
    }
}
