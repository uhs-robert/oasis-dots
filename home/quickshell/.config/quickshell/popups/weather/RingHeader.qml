pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.components
import qs.theme
import qs.services

// The current conditions as a ticked ring gauge around the temperature, with leader-line callouts beside it,
// then today's range, humidity and rain as hairline scales over a row of small readouts.
ColumnLayout {
    id: root

    readonly property var cur: WeatherState.current
    // The ring fills with the temperature over 0-100 °F in either unit.
    readonly property real fahrenheit: !WeatherState.has_data ? 0 : WeatherState.temp_f(root.cur.temp)
    readonly property var hum_vital: WeatherState.vital("hum")
    readonly property var rain_vital: WeatherState.vital("rain")
    readonly property var readouts: WeatherState.vitals.filter(v => ["wind", "uv", "aqi"].includes(v.key))

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    function ring_fraction(t) {
        return Math.max(0, Math.min(1, WeatherState.temp_f(t) / 100));
    }

    component CapsLabel: Text {
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 2.5
    }

    component ScaleValue: Text {
        color: Style.text_strong
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        font.letterSpacing: 0.5
    }

    // Sized from the widest text each column holds, so the scales start and end in line.
    TextMetrics {
        id: label_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 2.5
        text: "HUMIDITY"
    }

    TextMetrics {
        id: value_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
        font.letterSpacing: 0.5
        text: "100°F"
    }

    // One vital as a hairline scale: quarter ticks, a lit run up to `fill` and a taller marker at its end.
    component Scale: RowLayout {
        id: scale
        property string label: ""
        property string low: ""
        property string value_text: ""
        property real fill: 0

        readonly property real clamped_fill: Math.max(0, Math.min(1, scale.fill))

        Layout.fillWidth: true
        spacing: 8

        CapsLabel {
            Layout.preferredWidth: label_metrics.advanceWidth + 2
            text: scale.label
        }

        ScaleValue {
            Layout.preferredWidth: value_metrics.advanceWidth
            horizontalAlignment: Text.AlignRight
            color: Style.text_muted
            text: scale.low
        }

        Item {
            id: track
            Layout.fillWidth: true
            Layout.preferredHeight: 9

            readonly property real mid_y: Math.round(track.height / 2)

            Rectangle {
                y: track.mid_y
                width: track.width
                height: 1
                color: Style.hairline_dim
            }

            Repeater {
                model: 5

                Rectangle {
                    required property int index
                    x: Math.round(index / 4 * (track.width - 1))
                    y: track.mid_y - 2
                    width: 1
                    height: 5
                    color: Style.hairline_dim
                }
            }

            Rectangle {
                y: track.mid_y - 0.5
                width: Math.round(track.width * scale.clamped_fill)
                height: 2
                color: Style.text_strong
            }

            Rectangle {
                x: Math.round(track.width * scale.clamped_fill) - 1
                width: 1.5
                height: track.height
                color: Style.text_strong
            }
        }

        ScaleValue {
            Layout.preferredWidth: value_metrics.advanceWidth
            text: scale.value_text
        }
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        RingGauge {
            id: ring
            Layout.preferredWidth: Math.round(Math.max(84, Math.min(112, root.width * 0.34)))
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            value: Math.max(0, Math.min(1, root.fahrenheit / 100))
            label: WeatherState.has_data ? root.fmt_temp(root.cur.temp) : WeatherState.failed ? "n/a" : "--°"
            unit: "NOW"
            label_size: width * 0.24

            // Today's low-to-high span as a band just inside the ring, bracketed by ticks across the bezel;
            // the ring's own fill ends where now sits inside it.
            Shape {
                id: day_span
                visible: WeatherState.has_vitals
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                readonly property real low_angle: -90 + 360 * root.ring_fraction(WeatherState.today_low)
                readonly property real high_angle: -90 + 360 * root.ring_fraction(WeatherState.today_high)

                function bracket_tick(angle) {
                    const a = angle * Math.PI / 180, r1 = ring.r - 6, r2 = ring.r + 9;
                    return "M" + (ring.c + r1 * Math.cos(a)).toFixed(2) + " " + (ring.c + r1 * Math.sin(a)).toFixed(2)
                        + "L" + (ring.c + r2 * Math.cos(a)).toFixed(2) + " " + (ring.c + r2 * Math.sin(a)).toFixed(2);
                }

                ShapePath {
                    strokeWidth: 2
                    strokeColor: Style.hairline_dim
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathAngleArc {
                        centerX: ring.c
                        centerY: ring.c
                        radiusX: ring.r - 3.5
                        radiusY: ring.r - 3.5
                        startAngle: day_span.low_angle
                        sweepAngle: day_span.high_angle - day_span.low_angle
                    }
                }

                ShapePath {
                    strokeWidth: 1.5
                    strokeColor: Style.hairline
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    PathSvg { path: day_span.bracket_tick(day_span.low_angle) + day_span.bracket_tick(day_span.high_angle) }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            Callout {
                Layout.fillWidth: true
                label: "Condition"
                value: WeatherState.cond_text(false)
                value_color: WeatherState.has_data || WeatherState.loading ? Style.text_strong : Theme.warning
            }

            Callout {
                Layout.fillWidth: true
                visible: WeatherState.has_data
                label: "Feels like"
                value: WeatherState.has_data ? root.fmt_temp(root.cur.feels) : ""
            }

            Callout {
                Layout.fillWidth: true
                visible: WeatherState.location_name !== ""
                label: "Location"
                value: WeatherState.location_name
                small: true
            }

            Callout {
                Layout.fillWidth: true
                visible: WeatherState.stale || (!WeatherState.has_data && !WeatherState.loading && WeatherState.error !== "")
                label: WeatherState.stale ? "Stale data" : "Error"
                value: WeatherState.error || ""
                value_color: Theme.warning
                small: true
            }
        }
    }

    ColumnLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        spacing: 4

        Scale {
            label: "Today"
            low: WeatherState.has_vitals ? root.fmt_temp(WeatherState.today_low) : ""
            value_text: WeatherState.has_vitals ? root.fmt_temp(WeatherState.today_high) : ""
            fill: WeatherState.temp_range_pos
        }

        Scale {
            label: "Humidity"
            value_text: root.hum_vital ? root.hum_vital.value + root.hum_vital.unit : ""
            fill: root.hum_vital ? root.hum_vital.fill : 0
        }

        Scale {
            label: "Rain"
            value_text: root.rain_vital ? root.rain_vital.value + root.rain_vital.unit : ""
            fill: root.rain_vital ? root.rain_vital.fill : 0
        }
    }

    RowLayout {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        spacing: 12

        Repeater {
            model: root.readouts

            ColumnLayout {
                id: readout
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: 0
                spacing: 1

                CapsLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: readout.modelData.label
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: readout.modelData.value + (readout.modelData.unit !== "" ? " " + readout.modelData.unit : "") + (readout.modelData.detail !== "" ? " " + readout.modelData.detail : "")
                    color: Style.text_strong
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-2)
                    font.letterSpacing: 0.5
                }
            }
        }
    }
}
