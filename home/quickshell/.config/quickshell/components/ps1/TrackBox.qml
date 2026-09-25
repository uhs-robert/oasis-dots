// home/quickshell/.config/quickshell/components/ps1/TrackBox.qml
import QtQuick
import "../../theme"

// A CD Player track number box; the playing (default) track is lit.
Rectangle {
    id: root

    property int number: 0
    property bool lit: false
    property real size: 18

    implicitWidth: digits.implicitWidth + 8
    implicitHeight: root.size
    radius: 2
    color: root.lit ? Qt.tint(Theme.bg_surface, Qt.alpha(Theme.blue, 0.5)) : Qt.alpha(Theme.bg_shadow, 0.5)
    border.width: 1
    border.color: root.lit ? Theme.theme_primary_light : Style.frame_border_color

    Digits {
        id: digits
        anchors.centerIn: parent
        text: String(root.number).padStart(2, "0")
        size: Math.round(root.size * 0.58)
        color: root.lit ? Theme.fg_strong : Style.text_dim
    }
}
