// home/quickshell/.config/quickshell/components/clock_marker/LitPillMarker.qml
import QtQuick
import "../../theme"

// ps2: the lit selection pill of the menus around the minutes, with a halo that breathes during a meeting.
MarkerBase {
    id: root

    // 0..1 scale of the halo.
    property real breath: 1

    implicitWidth: Math.ceil(Math.max(upcoming_width.advanceWidth, now_width.advanceWidth)) + 16
    implicitHeight: label.implicitHeight + 4

    // Sized from the widest of both states, so the minutes ticking down and a meeting starting never resize the clock.
    TextMetrics {
        id: upcoming_width
        font: root.text_font
        text: "00m"
    }

    TextMetrics {
        id: now_width
        font: root.text_font
        text: "Now"
    }

    Repeater {
        model: [2, 4, 6]

        Rectangle {
            required property int modelData
            anchors.fill: pill
            anchors.margins: -modelData
            radius: height / 2
            color: Qt.alpha(Style.selection_glow, Style.selection_glow.a * (0.5 - modelData * 0.06) * root.breath)
        }
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Style.selection_bg
        border.width: 1
        border.color: Style.selection_border
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.in_meeting ? "Now" : root.minutes + "m"
        textFormat: Text.PlainText
        color: Theme.fg_strong
        font: root.text_font
    }

    SequentialAnimation on breath {
        running: root.in_meeting && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1.8; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.breath = 1
    }
}
