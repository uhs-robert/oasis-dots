pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "../../lock/skins/goldeneye" as Watch
import "../../theme/Watch.js" as W

// The current conditions as the classic pause watch: warm segments left spanning today's low to high with now picked out,
// blue segments right for today's chance of rain, a green panel between, and a strip of LCD bars for TEMP, HUM and RAIN below.
Item {
    id: root

    readonly property var cur: WeatherState.current
    readonly property bool has: WeatherState.has_data && !!root.cur
    readonly property int aqi: WeatherState.aqi_now
    readonly property string digits: root.has ? String(Math.round(root.cur.temp)) : "--"
    readonly property real arc_w: 30
    readonly property real arc_thickness: 11
    readonly property real pad: 12
    readonly property real face_h: Math.round(Math.max(120, Math.min(150, root.width * 0.3)))
    readonly property real strip_h: 46

    // Counted from the bottom of the warm arc: the segment holding now, and how many are lit up to it.
    readonly property int now_segment: Math.min(W.warm.length - 1, Math.floor(WeatherState.temp_range_pos * W.warm.length))
    readonly property int range_lit: WeatherState.has_vitals ? root.now_segment + 1 : 0
    // SegmentArc indexes from the top, so now is the highest lit segment; the run under it dims so now reads as a marker, not a fill.
    readonly property var range_colors: W.warm.map((c, i) => {
        const now_index = W.warm.length - 1 - root.now_segment;
        if (i === now_index) return W.white;
        return i > now_index ? String(Qt.alpha(c, 0.5)) : c;
    })
    readonly property int rain_lit: WeatherState.has_vitals ? Math.round(WeatherState.today_pop / 100 * W.cold_lit.length) : 0

    readonly property var readouts: !root.has ? [] : [
        { label: "WIND", value: Math.round(root.cur.wind_speed) + " " + WeatherState.wind_dir_label(root.cur.wind_dir) },
        { label: "UV", value: root.cur.uv_index.toFixed(1) + " " + WeatherState.uv_band(root.cur.uv_index).label.toUpperCase() },
        { label: "AQI", value: root.aqi >= 0 ? root.aqi + " " + WeatherState.aqi_band(root.aqi).label.toUpperCase() : "--" }
    ]

    // Where the arcs' end segments sit, mirroring SegmentArc's geometry at its default 112° span over 8 segments, so the labels hug them.
    readonly property real arc_end_angle: (56 - 7) * Math.PI / 180
    readonly property real arc_h: root.face_h - 16
    readonly property real arc_a: root.arc_w - root.arc_thickness / 2
    readonly property real arc_b: root.arc_h / 2 - root.arc_thickness / 2
    readonly property real arc_end_inset: root.arc_w - root.arc_a * Math.cos(root.arc_end_angle)
    readonly property real arc_end_half_len: Math.hypot(root.arc_a * Math.sin(root.arc_end_angle), root.arc_b * Math.cos(root.arc_end_angle)) * (7 * Math.PI / 180)
    readonly property real arc_top_tip: 8 + root.arc_h / 2 - root.arc_b * Math.sin(root.arc_end_angle) - root.arc_end_half_len
    readonly property real arc_bottom_tip: 8 + root.arc_h / 2 + root.arc_b * Math.sin(root.arc_end_angle) + root.arc_end_half_len

    readonly property real frame_h: root.face_h + (WeatherState.has_vitals ? root.strip_h + 6 : 0)
    readonly property string facility: "FACILITY: " + (WeatherState.location_name !== "" ? WeatherState.location_name.toUpperCase() : "UNKNOWN")

    implicitHeight: facility_line.anchors.topMargin + facility_line.implicitHeight

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.frame_h
        radius: 10
        color: Style.wk.frame
        border.width: 2
        border.color: Style.wk.rim
    }

    Watch.SegmentArc {
        x: 6
        y: 8
        width: root.arc_w
        height: root.arc_h
        thickness: root.arc_thickness
        colors: root.range_colors
        from_bottom: true
        lit: root.range_lit
    }

    ArcEndLabel {
        visible: WeatherState.has_vitals
        center_x: 6 + root.arc_end_inset
        above: true
        text: String(Math.round(WeatherState.today_high))
    }

    ArcEndLabel {
        visible: WeatherState.has_vitals
        center_x: 6 + root.arc_end_inset
        text: String(Math.round(WeatherState.today_low))
    }

    Watch.SegmentArc {
        x: root.width - root.arc_w - 6
        y: 8
        width: root.arc_w
        height: root.arc_h
        thickness: root.arc_thickness
        mirror: true
        colors: W.cold_lit
        lit: root.rain_lit
    }

    ArcEndLabel {
        visible: WeatherState.has_vitals
        center_x: root.width - 6 - root.arc_end_inset
        above: true
        text: WeatherState.today_pop + "%"
    }

    ArcEndLabel {
        center_x: root.width - 6 - root.arc_end_inset
        text: "RAIN"
    }

    Repeater {
        model: [-1, 1]

        Rectangle {
            required property int modelData
            x: root.width / 2 + modelData * 5 - 2
            y: 2
            width: 4
            height: 6
            color: W.white
        }
    }

    Rectangle {
        x: root.width / 2 - 2.5
        y: root.face_h - 8
        width: 5
        height: 6
        color: W.white
    }

    Watch.PanelShape {
        id: panel
        x: root.arc_w + 12
        y: 11
        width: root.width - x * 2
        height: root.face_h - 22
        cut: 12
        notch_w: 6
        notch_h: 18
        top_color: Style.wk.panel_top
        edge: Style.wk.edge
        bottom_color: Style.wk.panel_bottom

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.pad + 4
            anchors.rightMargin: root.pad + 4
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Row {
                    spacing: 4

                    Text {
                        text: root.digits
                        color: root.has ? Style.wk.lit : Style.wk.dim
                        font.family: W.digit_font
                        font.pixelSize: Style.font_size * 2 + 4
                    }

                    Text {
                        text: "°" + WeatherState.unit_symbol()
                        color: Style.wk.mid
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-1)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.topMargin: 2
                    elide: Text.ElideRight
                    text: root.has ? root.cur.cond : WeatherState.loading ? "Loading" : "Unavailable"
                    color: root.has || WeatherState.loading ? Style.wk.mid : Style.pal.error
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-3)
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Text {
                    visible: root.has
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: "FEELS LIKE " + (root.has ? Math.round(root.cur.feels) + "°" + WeatherState.unit_symbol() : "")
                    color: Style.wk.soft
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                }

                // The readout column drops out on a narrow panel; its readings run on one line here instead.
                Text {
                    visible: root.has && !readout_column.visible
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: root.readouts.map(r => r.label + " " + r.value).join("  ")
                    color: Style.wk.soft
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                }

                Text {
                    visible: WeatherState.stale || WeatherState.failed
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: (WeatherState.failed ? "NO DATA" : "STALE DATA") + (WeatherState.error ? ": " + WeatherState.error : "")
                    color: Style.pal.error
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                }
            }

            ColumnLayout {
                id: readout_column
                // The value cap reads this rather than the column's own width, which its rows feed back into.
                readonly property real readout_w: Math.min(160, panel.width * 0.4)
                visible: root.has && panel.width >= 260
                Layout.preferredWidth: readout_column.readout_w
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                Repeater {
                    model: root.readouts

                    RowLayout {
                        id: readout_row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            text: readout_row.modelData.label
                            color: Style.wk.soft
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            clip: true
                            text: "·".repeat(40)
                            color: Qt.alpha(Style.wk.dim, 0.6)
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }

                        Text {
                            Layout.maximumWidth: readout_column.readout_w * 0.75
                            elide: Text.ElideRight
                            text: readout_row.modelData.value
                            color: Style.wk.lit
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }
                    }
                }
            }
        }
    }

    Watch.PanelShape {
        visible: WeatherState.has_vitals
        x: 10
        y: root.face_h
        width: root.width - 20
        height: root.strip_h
        cut: 8
        notches: false
        top_color: Style.wk.panel_top
        edge: Style.wk.edge
        bottom_color: Style.wk.panel_bottom

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 5
            anchors.bottomMargin: 6
            spacing: root.width >= 300 ? 16 : 10

            LcdBar {
                label: "TEMP"
                value: root.has ? Math.round(root.cur.temp) + "°" : "--"
                low: String(Math.round(WeatherState.today_low))
                high: String(Math.round(WeatherState.today_high))
                fill: WeatherState.temp_range_pos
                marks_now: true
            }

            LcdBar {
                label: "HUM"
                value: root.has ? root.cur.humidity + "%" : "--"
                fill: root.has ? root.cur.humidity / 100 : 0
            }

            LcdBar {
                label: "RAIN"
                value: WeatherState.today_pop + "%"
                fill: WeatherState.today_pop / 100
            }
        }
    }

    // A small numeral printed on the bezel just past one end of an arc.
    component ArcEndLabel: Text {
        property real center_x: 0
        property bool above: false
        x: Math.round(center_x - width / 2)
        y: Math.round(above ? Math.max(2, root.arc_top_tip - height) : Math.min(root.face_h - height - 2, root.arc_bottom_tip))
        color: Style.wk.soft
        font.family: W.mono_font
        font.pixelSize: Style.fs(-6)
    }

    // A labelled LCD segment bar; with `marks_now` the segment holding `fill` lights brighter than the run below it.
    component LcdBar: ColumnLayout {
        id: lcd_bar
        property string label: ""
        property string value: ""
        property string low: ""
        property string high: ""
        property real fill: 0
        property bool marks_now: false
        readonly property int now_segment: Math.min(lcd_segments.count - 1, Math.floor(lcd_bar.fill * lcd_segments.count))

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.minimumWidth: 0
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: lcd_bar.label
                color: Style.wk.soft
                font.family: W.mono_font
                font.pixelSize: Style.fs(-5)
                font.letterSpacing: 1
            }

            Item { Layout.fillWidth: true }

            Text {
                text: lcd_bar.value
                color: Style.wk.lit
                font.family: W.mono_font
                font.pixelSize: Style.fs(-4)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            LcdEnd {
                visible: lcd_bar.low !== ""
                text: lcd_bar.low
            }

            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 20
                Layout.preferredHeight: 7

                SegBar {
                    id: lcd_segments
                    anchors.fill: parent
                    count: 10
                    gap: 2
                    last_lit: lcd_bar.marks_now ? lcd_bar.now_segment - 1 : Math.round(lcd_bar.fill * count) - 1
                    on_color: lcd_bar.marks_now ? Style.wk.dim : Style.wk.mid
                    off_color: Qt.alpha(Style.wk.dim, 0.25)
                }

                SegBar {
                    visible: lcd_bar.marks_now
                    anchors.fill: parent
                    count: lcd_segments.count
                    gap: lcd_segments.gap
                    first_lit: lcd_bar.now_segment
                    last_lit: lcd_bar.now_segment
                    on_color: W.white
                }
            }

            LcdEnd {
                visible: lcd_bar.high !== ""
                text: lcd_bar.high
            }
        }
    }

    // The briefing's facility line sits under the watch, so it shows on every tab instead of heading Daily and Alerts.
    ColumnLayout {
        id: facility_line
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.frame_h + 6
        spacing: 4

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: root.facility
            color: Style.text_fg
            font.family: Style.font_family
            font.pixelSize: Style.fs(-4)
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.alpha(Style.accent_color, 0.3)
        }
    }

    component LcdEnd: Text {
        color: Style.wk.soft
        font.family: W.mono_font
        font.pixelSize: Style.fs(-5)
    }
}
