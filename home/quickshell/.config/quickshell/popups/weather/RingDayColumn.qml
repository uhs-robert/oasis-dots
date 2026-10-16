pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../components"
import "../../theme"
import "../../services"

// One day as a ring gauge under its condition icon, a ticked bezel round it and the reading inside, then the rain chance as a smaller ring.
// sub 0: the day's low-to-high span on the week's scale.
// 1: wind speed with a bezel tick at the gusts and a bearing marker. 2: UV index. 3: sunshine against the day's daylight.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property string label: ""
    property bool selected: false
    property real col_w: 0
    // The week's coldest low and warmest high, shared by every column so spans compare across days.
    property real scale_min: 0
    property real scale_max: 1
    property int sub: 0
    property real wind_max: 1

    readonly property bool has: !!root.day && root.day.max !== undefined
    readonly property int pop: root.has ? Math.round(root.day.pop || 0) : 0
    readonly property real inner_w: Math.max(10, root.width - 8)
    readonly property real dial: Math.max(40, Math.min(76, root.inner_w))
    readonly property color ink: Style.text_strong
    // Longest sunshine the sub can show when the day has no sunrise or sunset.
    readonly property real fallback_daylight: 14
    readonly property real daylight_hours: root.has ? root.daylight_of(root.day) : root.fallback_daylight

    function frac(v, lo, hi) {
        return Math.max(0, Math.min(1, (v - lo) / Math.max(0.01, hi - lo)));
    }

    function hm_minutes(hm) {
        const parts = (hm || "").split(":");
        return parts.length === 2 ? parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10) : -1;
    }

    function daylight_of(day) {
        const rise = root.hm_minutes(day.sunrise), set = root.hm_minutes(day.sunset);
        return rise >= 0 && set > rise ? (set - rise) / 60 : root.fallback_daylight;
    }

    // The reading's fraction of the ring, per sub.
    readonly property real fill: {
        if (!root.has) return 0;
        const d = root.day;
        return root.sub === 1 ? root.frac(d.wind_speed_max, 0, root.wind_max)
            : root.sub === 2 ? root.frac(d.uv_max, 0, 12)
            : root.sub === 3 ? root.frac(d.sunshine_hours, 0, root.daylight_hours)
            : 1;
    }

    readonly property color reading_color: root.sub === 2 && root.has ? WeatherState.uv_color(root.day.uv_max) : root.ink

    readonly property string center_text: {
        if (!root.has) return "";
        const d = root.day;
        return root.sub === 0 ? Math.round(d.max) + "°"
            : root.sub === 1 ? String(Math.round(d.wind_speed_max))
            : root.sub === 2 ? d.uv_max.toFixed(1)
            : d.sunshine_hours.toFixed(1);
    }

    // Two caption lines under the dial, the same slots on every sub so the columns line up.
    readonly property string caption: {
        if (!root.has) return "";
        const d = root.day;
        return root.sub === 0 ? Math.round(d.min) + "°"
            : root.sub === 1 ? WeatherState.compass_label(d.wind_dir)
            : root.sub === 2 ? WeatherState.uv_band(d.uv_max).label
            : "HRS";
    }

    readonly property string sub_caption: {
        if (!root.has) return "";
        const d = root.day;
        return root.sub === 0 ? "LOW"
            : root.sub === 1 ? "G " + Math.round(d.wind_gusts_max)
            : root.sub === 2 ? "UV"
            : "OF " + root.daylight_hours.toFixed(1);
    }

    component Arc: Shape {
        id: arc
        property real radius: 10
        property real from_fraction: 0
        property real to_fraction: 1
        property real line_width: 1.5
        property color color: root.ink
        property real track_alpha: 0.18

        readonly property real sweep: 360 * (arc.to_fraction - arc.from_fraction)

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(arc.color, arc.track_alpha)
            fillColor: "transparent"
            PathAngleArc { centerX: arc.width / 2; centerY: arc.height / 2; radiusX: arc.radius; radiusY: arc.radius; startAngle: 0; sweepAngle: 360 }
        }

        ShapePath {
            strokeWidth: arc.sweep > 0 ? arc.line_width : -1
            strokeColor: arc.color
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                centerX: arc.width / 2
                centerY: arc.height / 2
                radiusX: arc.radius
                radiusY: arc.radius
                startAngle: -90 + 360 * arc.from_fraction
                sweepAngle: arc.sweep
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.selected ? Style.selection_bg : "transparent"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        anchors.topMargin: 8
        anchors.bottomMargin: 6
        spacing: 3
        opacity: root.selected ? 1 : 0.62

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        WeatherIcon {
            Layout.alignment: Qt.AlignHCenter
            size: Math.max(18, Math.min(34, root.inner_w - 14))
            code: root.has ? root.day.code : 0
        }

        Item {
            Layout.fillHeight: true
        }

        Item {
            id: dial
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.dial
            Layout.preferredHeight: root.dial

            readonly property real c: dial.width / 2
            readonly property real r: dial.width / 2 - 8

            function bezel_ticks() {
                let d = "";
                const n = 24;
                for (let i = 0; i < n; i++) {
                    const a = i / n * Math.PI * 2 - Math.PI / 2, major = i % 6 === 0;
                    const r1 = dial.r + 4, r2 = dial.r + (major ? 7.5 : 5.5);
                    d += "M" + (dial.c + r1 * Math.cos(a)).toFixed(2) + " " + (dial.c + r1 * Math.sin(a)).toFixed(2)
                        + "L" + (dial.c + r2 * Math.cos(a)).toFixed(2) + " " + (dial.c + r2 * Math.sin(a)).toFixed(2);
                }
                return d;
            }

            function radial_tick(fraction, r1, r2) {
                const a = fraction * Math.PI * 2 - Math.PI / 2;
                return "M" + (dial.c + r1 * Math.cos(a)).toFixed(2) + " " + (dial.c + r1 * Math.sin(a)).toFixed(2)
                    + "L" + (dial.c + r2 * Math.cos(a)).toFixed(2) + " " + (dial.c + r2 * Math.sin(a)).toFixed(2);
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 1
                    strokeColor: Qt.alpha(root.ink, root.selected ? 0.55 : 0.3)
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathSvg { path: dial.bezel_ticks() }
                }

                // A reticle's crosshair: the four cardinal ticks reach in through the bezel on the selected day.
                ShapePath {
                    strokeWidth: root.selected ? 1.2 : -1
                    strokeColor: root.ink
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathSvg {
                        path: dial.radial_tick(0, dial.r - 5, dial.r + 9) + dial.radial_tick(0.25, dial.r - 5, dial.r + 9)
                            + dial.radial_tick(0.5, dial.r - 5, dial.r + 9) + dial.radial_tick(0.75, dial.r - 5, dial.r + 9)
                    }
                }

                // Gusts: a tick across the bezel where the day's strongest gust sits on the speed scale.
                ShapePath {
                    strokeWidth: root.sub === 1 && root.has ? 1.5 : -1
                    strokeColor: Style.text_primary
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathSvg { path: root.has ? dial.radial_tick(root.frac(root.day.wind_gusts_max, 0, root.wind_max), dial.r - 5, dial.r + 5) : "" }
                }
            }

            // Temp: the span between the low and the high on the week's scale. The other subs light from the top.
            Arc {
                anchors.fill: parent
                radius: dial.r
                line_width: root.sub === 0 ? 2.5 : 1.5
                color: root.reading_color
                from_fraction: root.sub === 0 && root.has ? root.frac(root.day.min, root.scale_min, root.scale_max) : 0
                to_fraction: root.sub === 0 && root.has
                    ? Math.max(from_fraction + 0.03, root.frac(root.day.max, root.scale_min, root.scale_max))
                    : root.fill
            }

            // Wind: the bearing as a marker on the inner ring.
            Shape {
                visible: root.sub === 1 && root.has
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 1
                    strokeColor: Qt.alpha(root.ink, 0.25)
                    fillColor: "transparent"
                    PathAngleArc { centerX: dial.c; centerY: dial.c; radiusX: dial.r - 6; radiusY: dial.r - 6; startAngle: 0; sweepAngle: 360 }
                }
            }

            Rectangle {
                visible: root.sub === 1 && root.has
                readonly property real a: ((root.has ? root.day.wind_dir : 0) - 90) * Math.PI / 180
                width: 5
                height: 5
                x: dial.c + (dial.r - 6) * Math.cos(a) - width / 2
                y: dial.c + (dial.r - 6) * Math.sin(a) - height / 2
                rotation: 45
                color: Style.text_primary
            }

            Text {
                anchors.centerIn: parent
                text: root.center_text
                color: root.reading_color
                font.family: Style.number_font
                font.weight: Font.ExtraLight
                font.pixelSize: Math.max(11, dial.width * (root.center_text.length > 3 ? 0.22 : 0.27))
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.caption
            color: root.sub === 2 && root.has ? root.reading_color : Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
            font.letterSpacing: 0.5
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: -2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.sub_caption
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.letterSpacing: 2
        }

        Item {
            Layout.fillHeight: true
        }

        Item {
            id: rain
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(48, root.dial)
            Layout.preferredHeight: rain.Layout.preferredWidth

            Arc {
                anchors.fill: parent
                radius: rain.width / 2 - 3
                color: Style.text_primary
                to_fraction: root.pop / 100
            }

            Text {
                anchors.centerIn: parent
                text: root.pop + "%"
                color: root.pop > 0 ? Style.text_strong : Style.text_muted
                font.family: Style.number_font
                font.pixelSize: Style.fs(-4)
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: -2
            horizontalAlignment: Text.AlignHCenter
            text: "RAIN"
            color: Style.text_muted
            font.family: Style.font_family
            font.pixelSize: Style.fs(-5)
            font.letterSpacing: 2
        }

        Item {
            Layout.fillHeight: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 2
            color: root.selected ? Style.hairline : Style.hairline_dim
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Reticle {
                visible: root.selected
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                color: Style.text_primary
                center_color: Style.text_primary
            }

            Text {
                text: root.label.toUpperCase()
                color: root.selected ? Style.text_strong : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-4)
                font.letterSpacing: root.inner_w >= 50 ? 1.5 : 0
            }
        }
    }
}
