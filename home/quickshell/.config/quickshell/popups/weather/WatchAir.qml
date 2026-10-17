import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.features.clock
import "../../theme/Watch.js" as W

// Hourly's Air sub-view as the pause watch's objectives screen: US AQI in 12-hour pages of the 24 hours, each hour a bar in its AQI category colour at its real clock position,
// the cursor hour's index on the LCD digits and the live pollutants below it as objectives, completed or failed by their category. h/l move the hour cursor, and crossing a page edge flips pages.
// A seam notch marks the page's start, which tells 8 a.m. from 8 p.m.
Item {
    id: root

    property int hour_cursor: 0
    // Called with the clicked hour index; the popup owns hour_cursor, so clicks report up rather than assign it locally.
    property var on_select: function (i) {}

    readonly property var slice: WeatherState.aq_hours.slice(0, 24)
    // The cursor is shared with the longer hourly range, so it is clamped to these 24 hours.
    readonly property int cursor_index: Math.max(0, Math.min(root.slice.length - 1, root.hour_cursor))
    readonly property var cursor_row: root.slice[root.cursor_index]
    readonly property var current: WeatherState.aq_current || ({ aqi: 0, pm25: 0, pm10: 0, ozone: 0 })
    readonly property bool ready: WeatherState.aq_has_data && !!WeatherState.aq_current && root.slice.length > 0

    readonly property int page_start: Math.floor(root.cursor_index / 12) * 12
    readonly property var window_rows: root.slice.slice(root.page_start, root.page_start + 12)
    // Clock hour of slice[0]; empty slots past the forecast's end continue counting from it.
    readonly property int first_clock_hour: root.slice.length ? root.slice[0].hour : 0

    readonly property real tick_min: 3
    readonly property real tick_w: 26
    // Room left above the tallest bar for the peak hour's printed value.
    readonly property real label_room: 22
    readonly property real bar_base: face.bezel_r - face.band + 2
    readonly property real bar_span: face.band - 4 - root.label_room - root.tick_min
    // One scale for all 24 hours so the pages compare.
    readonly property real aqi_top: Math.max(100, ...root.slice.map(r => r.aqi))
    readonly property real sensitive_radius: root.bar_base + root.tick_min + Math.min(1, 100 / root.aqi_top) * root.bar_span

    readonly property var peak_index: {
        let best = -1;
        let best_v = 0;
        for (let i = 0; i < root.window_rows.length; i++) {
            if (root.window_rows[i].aqi > best_v) {
                best = i;
                best_v = root.window_rows[i].aqi;
            }
        }
        return best;
    }

    // Upper limits of the EPA AQI categories per pollutant, in the units the air-quality feed reports (ug/m3); a value above the last limit is the top category.
    readonly property var pollutants: [
        { label: "PM2.5", key: "pm25", limits: [9, 35.4, 55.4, 125.4, 225.4] },
        { label: "PM10", key: "pm10", limits: [54, 154, 254, 354, 424] },
        { label: "OZONE", key: "ozone", limits: [106, 137, 167, 206, 392] }
    ]

    function category_of(value, limits) {
        const i = limits.findIndex(l => value <= l);
        return i < 0 ? limits.length : i;
    }

    function status_text(category) {
        return category === 0 ? "COMPLETED" : category === 1 ? "PENDING" : "FAILED";
    }

    function status_color(category) {
        return category === 0 ? Style.wk.lit : category === 1 ? W.warm[5] : W.red;
    }

    WatchFace {
        id: face
        anchors.fill: parent
        hand_hour: root.ready ? root.cursor_row.hour : -1
        seam_hour: root.ready ? root.window_rows[0].hour : -1
        band: 58

        bezel: [
            Rectangle {
                x: -root.sensitive_radius
                y: -root.sensitive_radius
                width: root.sensitive_radius * 2
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(W.red, 0.4)
            },
            Repeater {
                model: 12

                Item {
                    id: slot
                    required property int index
                    readonly property int slice_index: root.page_start + slot.index
                    readonly property var row: root.ready ? root.slice[slot.slice_index] : undefined
                    readonly property bool at_cursor: root.ready && slot.slice_index === root.cursor_index
                    readonly property bool is_peak: slot.index === root.peak_index
                    readonly property real norm: slot.row ? Math.min(1, slot.row.aqi / root.aqi_top) : 0
                    readonly property real len: root.tick_min + slot.norm * root.bar_span
                    readonly property real hour: slot.row ? slot.row.hour : (root.first_clock_hour + slot.slice_index) % 24
                    rotation: face.angle_of(slot.hour)

                    Rectangle {
                        visible: slot.at_cursor
                        x: -30
                        y: -face.bezel_r + 2
                        width: 60
                        height: face.band
                        radius: 3
                        color: Qt.alpha(Style.wk.lit, 0.18)
                    }

                    Rectangle {
                        visible: !slot.row
                        x: -root.tick_w / 2
                        y: -root.bar_base - root.tick_min
                        width: root.tick_w
                        height: root.tick_min
                        color: Style.wk.bar_off
                    }

                    Rectangle {
                        visible: !!slot.row
                        x: -root.tick_w / 2
                        y: -root.bar_base - slot.len
                        width: root.tick_w
                        height: slot.len
                        color: slot.row ? WeatherState.aqi_color(slot.row.aqi) : "transparent"
                        opacity: slot.at_cursor ? 1 : 0.55 + 0.35 * slot.norm
                    }

                    Rectangle {
                        visible: !!slot.row && slot.at_cursor
                        x: -root.tick_w / 2
                        y: -root.bar_base - slot.len - 2
                        width: root.tick_w
                        height: 2
                        color: W.white
                    }

                    Text {
                        id: peak_label
                        // Beyond the bar tip by half the label's extent along the radius, so a side bar's wide label clears it.
                        readonly property real reach: root.bar_base + slot.len + 3 + (Math.abs(Math.sin(slot.rotation * Math.PI / 180)) * width + Math.abs(Math.cos(slot.rotation * Math.PI / 180)) * height) / 2
                        visible: !!slot.row && slot.is_peak
                        x: -width / 2
                        y: -peak_label.reach - height / 2
                        text: slot.row ? slot.row.aqi : ""
                        color: W.white
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-6)
                        font.bold: true
                        rotation: -slot.rotation
                        transformOrigin: Item.Center
                    }

                    MouseArea {
                        x: -28
                        y: -face.bezel_r
                        width: 56
                        height: face.band
                        enabled: !!slot.row
                        onClicked: root.on_select(slot.slice_index)
                    }
                }
            }
        ]

        Text {
            visible: !root.ready
            anchors.centerIn: parent
            width: parent.width - 16
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: WeatherState.aq_loading ? "LOADING…" : "AIR QUALITY UNAVAILABLE"
            color: Style.wk.dim
            font.family: W.mono_font
            font.pixelSize: Style.fs(-3)
            font.letterSpacing: 1
        }

        ColumnLayout {
            visible: root.ready
            anchors.centerIn: parent
            width: parent.width - 4
            spacing: 2

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: date_label.implicitWidth + 14
                implicitHeight: date_label.implicitHeight + 4
                color: W.black
                border.width: 1
                border.color: Style.wk.rim

                Text {
                    id: date_label
                    anchors.centerIn: parent
                    text: face.span_text(root.window_rows[0], root.window_rows[root.window_rows.length - 1])
                    color: Style.wk.mid
                    font.family: W.mono_font
                    font.pixelSize: Style.fs(-4)
                    font.letterSpacing: 1
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.cursor_row ? TimeFormat.hour_of(root.cursor_row.hour) : ""
                color: Style.wk.lit
                font.family: W.mono_font
                font.pixelSize: Style.fs(1)
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.cursor_row ? root.cursor_row.aqi : "--"
                color: root.cursor_row ? WeatherState.aqi_color(root.cursor_row.aqi) : Style.wk.dim
                font.family: W.digit_font
                font.pixelSize: Style.fs(9)
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.cursor_row ? "AQI · " + WeatherState.aqi_band(root.cursor_row.aqi).label.replace("for Sensitive Groups", "(Sens.)").toUpperCase() : ""
                color: Style.wk.mid
                font.family: W.mono_font
                font.pixelSize: Style.fs(-5)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                implicitHeight: 1
                color: Style.wk.edge
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "OBJECTIVES · NOW AQI " + root.current.aqi
                color: Style.wk.dim
                font.family: W.mono_font
                font.pixelSize: Style.fs(-6)
                font.letterSpacing: 1
            }

            Repeater {
                model: root.pollutants

                RowLayout {
                    id: objective
                    required property var modelData
                    readonly property real value: root.current[objective.modelData.key]
                    readonly property int category: root.category_of(objective.value, objective.modelData.limits)
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 4

                    Text {
                        Layout.preferredWidth: 36
                        text: objective.modelData.label
                        color: Style.wk.mid
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-5)
                    }
                    Text {
                        Layout.preferredWidth: 30
                        horizontalAlignment: Text.AlignRight
                        text: objective.value.toFixed(1)
                        color: Style.wk.soft
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-5)
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: root.status_text(objective.category)
                        color: root.status_color(objective.category)
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-5)
                        font.bold: true
                    }
                }
            }
        }
    }
}
