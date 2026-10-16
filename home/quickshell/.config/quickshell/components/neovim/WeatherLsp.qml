import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.theme
import qs.services

// Weather as a Neovim buffer: a winbar breadcrumb, the conditions, the first alert as an LSP diagnostic on the location line,
// and today's vitals as a hover float.
ColumnLayout {
    id: root

    // Breadcrumb parts after "weather", e.g. the tab and its sub-view.
    property var trail: []
    readonly property var alert: WeatherState.alerts.length > 0 ? WeatherState.alerts[0] : null
    readonly property color diag: root.alert ? WeatherState.alert_color(root.alert.severity) : Theme.warning

    signal alert_clicked()

    spacing: 6

    readonly property int hover_px: Style.fs(-3)
    readonly property real hover_key_px: hover_metrics.advanceWidth("rain ")
    readonly property real hover_lead_px: hover_metrics.advanceWidth("-10 ")
    readonly property real hover_tail_px: hover_metrics.advanceWidth(" 100 °F")
    // Gauge cells fill what the key, low and high columns leave inside the float's padding.
    readonly property int gauge_cells: Math.max(5, Math.min(16, Math.floor((root.width - 20 - root.hover_key_px - root.hover_lead_px - root.hover_tail_px) / hover_metrics.advanceWidth("▰"))))
    readonly property var gauges: !WeatherState.has_vitals ? [] : [
        { key: "temp", lead: String(Math.round(WeatherState.today_low)), lead_color: WeatherState.temp_color(WeatherState.today_low), tail: " " + Math.round(WeatherState.today_high) + " °" + WeatherState.unit_symbol(), vital: WeatherState.vital("temp") },
        { key: "hum", lead: "", lead_color: Style.text_fg, tail: " " + WeatherState.vital("hum").value + "%", vital: WeatherState.vital("hum") },
        { key: "rain", lead: "", lead_color: Style.text_fg, tail: " " + WeatherState.today_pop + "%", vital: WeatherState.vital("rain") }
    ]
    readonly property var readouts: !WeatherState.has_vitals ? [] : ["wind", "uv", "aqi"].map(k => WeatherState.vital(k)).filter(v => v.key !== "aqi" || WeatherState.aqi_now >= 0)

    // The temp gauge marks a position in today's range, so it lights through now's cell; the others fill to an amount.
    function lit_cells(gauge) {
        return gauge.key === "temp" ? Math.round(gauge.vital.fill * (root.gauge_cells - 1)) + 1 : Math.round(gauge.vital.fill * root.gauge_cells);
    }

    function fmt_temp(t) {
        return Math.round(t) + "°" + WeatherState.unit_symbol();
    }

    Row {
        spacing: 6

        Text {
            text: "\u{f0c2}"
            color: Style.text_primary
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Repeater {
            model: ["weather"].concat(root.trail.filter(t => t !== ""))

            Row {
                id: crumb
                required property string modelData
                required property int index
                readonly property bool last: crumb.index === root.trail.filter(t => t !== "").length
                spacing: 6

                Text {
                    visible: crumb.index > 0
                    text: "›"
                    color: Style.text_muted
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }

                Text {
                    text: crumb.modelData
                    color: crumb.last ? Style.text_fg : Style.text_dim
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                    font.bold: crumb.last
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Image {
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            Layout.preferredWidth: Style.px(48)
            Layout.preferredHeight: Style.px(48)
            visible: WeatherState.has_data
            source: WeatherState.has_data ? WeatherState.icon_source(WeatherState.current.code, WeatherState.current.is_day) : ""
            sourceSize.width: Math.ceil(96 * dpr)
            sourceSize.height: Math.ceil(96 * dpr)
            smooth: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Row {
                spacing: 10

                Text {
                    id: temp_text
                    text: WeatherState.has_data ? root.fmt_temp(WeatherState.current.temp) : WeatherState.failed ? "n/a" : "--°"
                    color: Style.text_strong
                    font.family: Style.number_font
                    font.pixelSize: Style.fs(15)
                    font.bold: true
                }

                Text {
                    anchors.baseline: temp_text.baseline
                    text: WeatherState.cond_text(true)
                    color: WeatherState.has_data || WeatherState.loading ? Style.text_fg : Theme.warning
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-1)
                }
            }

            Text {
                visible: WeatherState.has_data
                text: "Feels like " + (WeatherState.has_data ? root.fmt_temp(WeatherState.current.feels) : "") + (WeatherState.stale ? "  ·  stale" : "")
                color: Style.text_dim
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }

    Item {
        visible: WeatherState.location_name !== ""
        Layout.fillWidth: true
        implicitHeight: location_text.implicitHeight + 4

        Text {
            visible: !!root.alert
            width: 22
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: location_text.verticalCenter
            text: "\u{f071}"
            color: root.diag
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Text {
            id: location_text
            x: 30
            width: Math.min(implicitWidth, parent.width - x)
            elide: Text.ElideRight
            text: WeatherState.location_name
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)
        }

        // Undercurl, drawn once.
        Shape {
            visible: !!root.alert
            x: location_text.x
            y: location_text.y + location_text.height
            width: location_text.width
            height: 4

            ShapePath {
                strokeColor: root.diag
                strokeWidth: 1
                fillColor: "transparent"
                PathSvg {
                    path: {
                        let d = "M0 2";
                        for (let x = 0; x < location_text.width; x += 4) d += " Q" + (x + 1) + " 0 " + (x + 2) + " 2 Q" + (x + 3) + " 4 " + (x + 4) + " 2";
                        return d;
                    }
                }
            }
        }
    }

    Row {
        visible: !!root.alert
        Layout.leftMargin: 30
        Layout.fillWidth: true
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "└──"
            color: Qt.tint(Style.frame_color, Qt.alpha(root.diag, 0.55))
            font.family: Style.font_family
            font.pixelSize: Style.fs(-3)
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(event_text.implicitWidth, Math.max(40, root.width - 150)) + 14
            height: event_text.implicitHeight + 2
            radius: 3
            color: Qt.alpha(root.diag, 0.13)

            Text {
                id: event_text
                anchors.centerIn: parent
                width: parent.width - 14
                elide: Text.ElideRight
                text: root.alert ? "■ " + root.alert.event + (WeatherState.alerts.length > 1 ? "  +" + (WeatherState.alerts.length - 1) : "") : ""
                color: root.diag
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.alert ? WeatherState.fmt_until(root.alert.ends) : ""
            color: Qt.tint(Style.text_dim, Qt.alpha(root.diag, 0.6))
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }

        TapHandler {
            onTapped: root.alert_clicked()
        }
    }

    FontMetrics {
        id: hover_metrics
        font.family: Style.font_family
        font.pixelSize: root.hover_px
    }

    Item {
        visible: WeatherState.has_vitals
        Layout.fillWidth: true
        implicitHeight: hover_body.implicitHeight + 12

        FloatFrame {
            anchors.fill: parent
            chip_height: 0
            fill: Qt.tint(Style.frame_color, Qt.alpha(Style.text_fg, 0.04))
        }

        ColumnLayout {
            id: hover_body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 6
            spacing: 1

            Repeater {
                model: root.gauges

                Row {
                    id: gauge_row
                    required property var modelData
                    readonly property int lit: root.lit_cells(gauge_row.modelData)

                    Text {
                        width: root.hover_key_px
                        text: gauge_row.modelData.key
                        color: Style.text_primary
                        font.family: Style.font_family
                        font.pixelSize: root.hover_px
                    }

                    Text {
                        width: root.hover_lead_px
                        horizontalAlignment: Text.AlignRight
                        rightPadding: hover_metrics.advanceWidth(" ")
                        text: gauge_row.modelData.lead
                        color: gauge_row.modelData.lead_color
                        font.family: Style.font_family
                        font.pixelSize: root.hover_px
                    }

                    Text {
                        text: "▰".repeat(gauge_row.lit)
                        color: gauge_row.modelData.vital.color
                        font.family: Style.font_family
                        font.pixelSize: root.hover_px
                    }

                    Text {
                        text: "▱".repeat(root.gauge_cells - gauge_row.lit)
                        color: Style.text_muted
                        font.family: Style.font_family
                        font.pixelSize: root.hover_px
                    }

                    Text {
                        text: gauge_row.modelData.tail
                        color: gauge_row.modelData.key === "temp" ? WeatherState.temp_color(WeatherState.today_high) : Style.text_fg
                        font.family: Style.font_family
                        font.pixelSize: root.hover_px
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 3
                Layout.bottomMargin: 3
                implicitHeight: 1
                color: Style.frame_border_color
            }

            Flow {
                Layout.fillWidth: true
                spacing: 14

                Repeater {
                    model: root.readouts

                    Row {
                        id: readout
                        required property var modelData
                        spacing: hover_metrics.advanceWidth(" ")

                        Text {
                            text: readout.modelData.label.toLowerCase()
                            color: Style.text_primary
                            font.family: Style.font_family
                            font.pixelSize: root.hover_px
                        }

                        Text {
                            text: readout.modelData.value + (readout.modelData.unit !== "" ? " " + readout.modelData.unit : "")
                            color: readout.modelData.color
                            font.family: Style.font_family
                            font.pixelSize: root.hover_px
                        }

                        Text {
                            text: readout.modelData.detail
                            color: Style.text_dim
                            font.family: Style.font_family
                            font.pixelSize: root.hover_px
                        }
                    }
                }
            }
        }
    }
}
