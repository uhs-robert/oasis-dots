// home/quickshell/.config/quickshell/popups/weather/WeaponSlots.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../services"

// Days as HL1 weapon-slot buckets numbered along the top; the selected one opens wider, rain chance is its ammo bar.
Item {
    id: root

    property var days: []
    property int first_day: 0
    property int day_cursor: 0
    property var on_select: function (i) {}

    readonly property real gap: 4
    readonly property real open_weight: 1.75
    readonly property int count: root.days.length
    readonly property real unit: root.count > 0 ? (root.width - root.gap * (root.count - 1)) / (root.count - 1 + root.open_weight) : 0
    readonly property color hl: Style.text_primary
    readonly property color hl_t: Style.text_muted

    readonly property real bar_h: 18
    // Space left for the open bucket once the number bar is out of the way.
    readonly property real bucket_h: Math.max(80, root.height - root.bar_h)
    readonly property real open_inner_w: Math.floor(root.unit * root.open_weight) - 14
    // Grows the open bucket's contents so it fills tall Daily areas instead of sitting content-sized.
    readonly property real bucket_scale: Math.max(1, Math.min(2.2, root.bucket_h / 130))
    readonly property real closed_scale: Math.max(1, Math.min(1.5, root.bucket_scale))
    readonly property real stat_size: Style.font_size - 6 + Math.round((root.bucket_scale - 1) * 3)
    readonly property real temps_scale: Math.max(1, Math.min(root.bucket_scale, (root.open_inner_w - 2) / Math.max(1, probe_temps.implicitWidth)))

    Temps {
        id: probe_temps
        visible: false
        hi_size: 20
        lo_size: 14
        day: root.days.length > 0 ? root.days[0] : null
    }

    Row {
        id: slots_row
        spacing: root.gap

        Repeater {
            model: root.days

            Column {
                id: slot
                required property var modelData
                required property int index
                readonly property int day_index: root.first_day + slot.index
                readonly property bool open: slot.day_index === root.day_cursor

                width: Math.floor(root.unit * (slot.open ? root.open_weight : 1))
                spacing: 0

                Rectangle {
                    width: parent.width
                    height: root.bar_h
                    color: slot.open ? root.hl : "transparent"
                    border.width: slot.open ? 0 : 1
                    border.color: Style.hairline_dim

                    Text {
                        id: slot_number
                        width: 17
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: String(slot.index + 1)
                        color: slot.open ? Theme.bg_crust : root.hl
                        font.family: Style.number_font
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        x: slot_number.width
                        width: 1
                        height: parent.height
                        color: slot.open ? Qt.alpha(Theme.bg_crust, 0.4) : Style.hairline_dim
                    }

                    Text {
                        x: slot_number.width + 5
                        width: parent.width - x - 3
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: (slot.open || slot.width >= 60 ? slot.modelData.weekday : Qt.formatDate(new Date(slot.modelData.date + "T00:00:00"), "ddd")).toUpperCase()
                        color: slot.open ? Theme.bg_crust : root.hl_t
                        font.family: Style.font_family
                        font.pixelSize: Style.font_size - 6
                        font.bold: true
                        font.letterSpacing: slot.open ? 1.3 : 0.5
                    }
                }

                Rectangle {
                    id: bucket_box
                    width: parent.width
                    height: root.bucket_h
                    color: slot.open ? Style.selection_bg : "transparent"
                    border.width: slot.open ? 1 : 0
                    border.color: Style.hairline

                    // Closed buckets hang open-topped from their number bar.
                    Repeater {
                        model: slot.open ? [] : [[0, 0, 1, 1], [1, 0, 1, 1], [0, 1, 1, 0]]

                        Rectangle {
                            required property var modelData
                            x: modelData[0] * ((parent ? parent.width : 0) - 1)
                            y: modelData[1] * ((parent ? parent.height : 0) - 1)
                            width: modelData[2] ? 1 : (parent ? parent.width : 0)
                            height: modelData[3] ? (parent ? parent.height : 0) : 1
                            color: Style.hairline_dim
                        }
                    }

                    ColumnLayout {
                        visible: slot.open
                        x: 7
                        y: 6
                        width: parent.width - 14
                        height: bucket_box.height - 14
                        spacing: 3 * root.bucket_scale

                        DayIcon {
                            code: slot.modelData.code
                            size: Math.min(26 * root.bucket_scale, root.open_inner_w * 0.6)
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        Temps {
                            hi_size: 20 * root.temps_scale
                            lo_size: 14 * root.temps_scale
                            day: slot.modelData
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: slot.modelData.cond.toUpperCase()
                            color: root.hl
                            font.family: Style.font_family
                            font.pixelSize: root.stat_size
                            font.bold: true
                            font.letterSpacing: 1.4
                        }

                        Stat {
                            label: "RAIN"
                            value: slot.modelData.pop + "%"
                            value_color: Theme.info
                        }

                        AmmoBar {
                            pop: slot.modelData.pop
                            Layout.preferredHeight: Math.round(4 * Math.min(root.bucket_scale, 1.8))
                        }

                        Stat {
                            label: "WIND"
                            value: Math.round(slot.modelData.wind_speed_max) + " " + WeatherState.wind_unit()
                        }

                        Stat {
                            label: "UV"
                            value: slot.modelData.uv_max.toFixed(1)
                        }
                    }

                    ColumnLayout {
                        visible: !slot.open
                        x: 5
                        y: 8
                        width: parent.width - 10
                        height: bucket_box.height - 16
                        spacing: 3 * root.closed_scale

                        DayIcon {
                            Layout.alignment: Qt.AlignHCenter
                            code: slot.modelData.code
                            size: Math.min(22 * root.bucket_scale, slot.width - 18)
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        FitText {
                            text: Math.round(slot.modelData.max) + "°"
                            color: Theme.fg_strong
                            font.pixelSize: 15 * root.closed_scale
                            font.bold: true
                        }

                        FitText {
                            text: Math.round(slot.modelData.min) + "°"
                            color: root.hl_t
                            font.pixelSize: 12 * root.closed_scale
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        FitText {
                            text: slot.modelData.pop + "%"
                            color: Theme.info
                            font.pixelSize: (Style.font_size - 5) * Math.min(root.closed_scale, 1.3)
                            font.bold: true
                        }

                        AmmoBar {
                            pop: slot.modelData.pop
                            Layout.preferredHeight: Math.round(3 * Math.min(root.bucket_scale, 1.8))
                        }
                    }
                }

                TapHandler {
                    onTapped: root.on_select(slot.day_index)
                }
            }
        }
    }

    component DayIcon: Item {
        id: day_icon
        property int code: 0
        property real size: 22
        implicitWidth: day_icon.size
        implicitHeight: day_icon.size

        Image {
            id: icon_image
            anchors.fill: parent
            visible: false
            readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
            sourceSize.width: Math.ceil(2 * day_icon.size * dpr)
            sourceSize.height: Math.ceil(2 * day_icon.size * dpr)
            source: WeatherState.icon_source(day_icon.code, true)
            smooth: true
        }

        MultiEffect {
            anchors.fill: parent
            source: icon_image
            colorization: 1
            colorizationColor: root.hl
        }
    }

    component Temps: RowLayout {
        id: temps
        property var day: null
        property real hi_size: 13
        property real lo_size: 13
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignBaseline
            text: temps.day ? Math.round(temps.day.max) + "°" : ""
            color: Theme.fg_strong
            font.family: Style.number_font
            font.pixelSize: temps.hi_size
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignBaseline
            text: temps.day ? Math.round(temps.day.min) + "°" : ""
            color: root.hl_t
            font.family: Style.number_font
            font.pixelSize: temps.lo_size
        }
    }

    component Stat: RowLayout {
        id: stat
        property string label: ""
        property string value: ""
        property color value_color: Theme.fg_strong
        property real font_size: root.stat_size
        Layout.fillWidth: true
        spacing: 4

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: stat.label
            color: root.hl_t
            font.family: Style.font_family
            font.pixelSize: stat.font_size
            font.bold: true
            font.letterSpacing: 1.5
        }

        Text {
            text: stat.value
            color: stat.value_color
            font.family: Style.number_font
            font.pixelSize: stat.font_size + 1
            font.bold: true
        }
    }

    component AmmoBar: Rectangle {
        id: ammo
        property real pop: 0
        Layout.fillWidth: true
        color: Style.meter_off

        Rectangle {
            width: ammo.width * Math.max(0, Math.min(100, ammo.pop)) / 100
            height: ammo.height
            color: Theme.info
        }
    }

    component FitText: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 8
        font.family: Style.number_font
    }
}
