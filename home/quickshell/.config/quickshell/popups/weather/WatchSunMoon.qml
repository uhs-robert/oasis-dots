import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../../theme"
import "../../services"
import "../../lock/skins/goldeneye" as Watch
import "../../theme/Watch.js" as W

// Daily's Sun & Moon sub-view on the pause watch's 24-hour dial laid out like a sundial, noon at the top: the selected day's daylight shaded on the bezel between
// sunrise on the left and sunset on the right, today's sun as the hand, the moon in a date-window aperture on the face. The Daily day window runs above as a strip.
Item {
    id: root

    property int day_cursor: 0
    property int first_day: 0
    property int day_span: 5
    property var on_select: function (i) {}

    readonly property var day: WeatherState.days[Math.max(0, Math.min(WeatherState.days.length - 1, root.day_cursor))]
    readonly property bool is_today: root.day_cursor === 0

    readonly property var moon_times: root.day ? WeatherState.moon_times_for_date(root.day.date) : ({ rise: null, set: null })
    readonly property real moon_phase: root.day ? WeatherState.moon_phase_for_date(root.day.date) : 0
    readonly property string next_full: root.day ? WeatherState.next_full_moon_label(root.day.date) : ""

    readonly property real rise_hour: root.hour_of(root.day ? root.day.sunrise : "")
    readonly property real set_hour: root.hour_of(root.day ? root.day.sunset : "")
    readonly property bool has_daylight: root.rise_hour >= 0 && root.set_hour > root.rise_hour
    property real now_hour: root.location_hour()
    readonly property bool sun_up: root.has_daylight && root.now_hour >= root.rise_hour && root.now_hour <= root.set_hour
    readonly property color sun_color: W.warm[5]

    function hour_of(hm) {
        if (!hm) return -1;
        const parts = hm.split(":");
        if (parts.length !== 2) return -1;
        return parseInt(parts[0], 10) + parseInt(parts[1], 10) / 60;
    }

    function location_hour() {
        const loc = WeatherState.location_now();
        return loc.getUTCHours() + loc.getUTCMinutes() / 60;
    }

    function day_length() {
        if (!root.has_daylight) return "--";
        const mins = Math.round((root.set_hour - root.rise_hour) * 60);
        return Math.floor(mins / 60) + "h " + (mins % 60) + "m";
    }

    Timer {
        interval: 60000
        running: root.is_today
        repeat: true
        onTriggered: root.now_hour = root.location_hour()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: WeatherState.days.slice(root.first_day, root.first_day + root.day_span)

                Item {
                    id: day_cell
                    required property var modelData
                    required property int index
                    readonly property int day_index: root.first_day + day_cell.index
                    readonly property bool selected: day_cell.day_index === root.day_cursor

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: day_text.implicitHeight + 14

                    Watch.PanelShape {
                        visible: day_cell.selected
                        anchors.fill: parent
                        cut: 6
                        notches: false
                        top_color: Style.wk.panel_top
                        bottom_color: Style.wk.panel_bottom
                        edge: Style.wk.edge
                    }

                    Rectangle {
                        visible: day_cell.selected
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 16
                        height: 2
                        color: Style.caret_color
                    }

                    Text {
                        id: day_text
                        anchors.centerIn: parent
                        width: parent.width - 4
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: day_cell.modelData.weekday.toUpperCase()
                        color: day_cell.selected ? Style.wk.lit : Style.wk.mid
                        opacity: day_cell.selected ? 1 : 0.7
                        font.family: W.head_font
                        font.pixelSize: Style.fs(-5)
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.on_select(day_cell.day_index)
                    }
                }
            }
        }

        WatchFace {
            id: face
            Layout.fillWidth: true
            Layout.fillHeight: true
            hours_per_turn: 24
            top_hour: 12
            hand_hour: root.is_today ? root.now_hour : -1
            hand_color: root.sun_color
            hand_alpha: root.sun_up ? 1 : 0.45

            bezel: Item {
                Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 10
                        strokeColor: Style.wk.bar_off
                        fillColor: "transparent"
                        PathAngleArc { radiusX: face.bezel_r - 14; radiusY: face.bezel_r - 14; startAngle: 0; sweepAngle: 360 }
                    }

                    ShapePath {
                        strokeWidth: 10
                        strokeColor: root.sun_color
                        fillColor: "transparent"
                        capStyle: ShapePath.FlatCap
                        PathAngleArc {
                            radiusX: face.bezel_r - 14
                            radiusY: face.bezel_r - 14
                            startAngle: root.has_daylight ? face.angle_of(root.rise_hour) - 90 : 0
                            sweepAngle: root.has_daylight ? (root.set_hour - root.rise_hour) / 24 * 360 : 0
                        }
                    }
                }

                Repeater {
                    model: root.has_daylight ? [root.rise_hour, root.set_hour] : []

                    Rectangle {
                        required property real modelData
                        x: -1
                        y: -face.bezel_r + 2
                        width: 2
                        height: face.band - 4
                        color: W.white
                        transform: Rotation { origin.x: 1; origin.y: face.bezel_r - 2; angle: face.angle_of(modelData) }
                    }
                }

                Repeater {
                    model: root.has_daylight ? [
                        { hour: root.rise_hour, text: WeatherState.fmt_hm(root.day.sunrise), caption: "RISE" },
                        { hour: root.set_hour, text: WeatherState.fmt_hm(root.day.sunset), caption: "SET" }
                    ] : []

                    Column {
                        required property var modelData
                        readonly property real theta: face.angle_of(modelData.hour) * Math.PI / 180
                            x: (face.bezel_r - face.band - 12) * Math.sin(theta) - width / 2
                        y: -(face.bezel_r - face.band - 12) * Math.cos(theta) - height / 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.caption
                            color: Style.wk.dim
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-6)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.text
                            color: root.sun_color
                            font.family: W.mono_font
                            font.pixelSize: Style.fs(-4)
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
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
                        text: root.day ? Qt.formatDate(new Date(root.day.date + "T00:00:00"), "ddd MMM d").toUpperCase() : ""
                        color: Style.wk.mid
                        font.family: W.mono_font
                        font.pixelSize: Style.fs(-4)
                        font.letterSpacing: 1
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: 28
                    color: W.black
                    border.width: 2
                    border.color: Style.wk.rim

                    Image {
                        anchors.centerIn: parent
                        width: 46
                        height: 46
                        source: WeatherState.moon_icon_source(root.moon_phase)
                        sourceSize.width: 92
                        sourceSize.height: 92
                        smooth: true
                    }
                }

                FaceText {
                    text: WeatherState.moon_name(root.moon_phase).toUpperCase()
                    color: Style.wk.lit
                }

                FaceText {
                    text: "MOONRISE " + (root.moon_times.rise || "--")
                }

                FaceText {
                    visible: !!root.moon_times.set
                    text: "MOONSET " + (root.moon_times.set || "")
                }

                FaceText {
                    text: "FULL MOON " + root.next_full.toUpperCase()
                    color: Style.wk.soft
                }

                FaceText {
                    text: "DAYLIGHT " + root.day_length()
                    color: root.sun_color
                }
            }
        }
    }

    component FaceText: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: Style.wk.mid
        font.family: W.mono_font
        font.pixelSize: Style.fs(-4)
    }
}
