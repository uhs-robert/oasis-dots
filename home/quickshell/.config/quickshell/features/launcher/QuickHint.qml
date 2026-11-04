import QtQuick
import qs.theme
import "BrowseLayout.js" as BrowseLayout

// The digit that selects a browse item in NORMAL mode, on the first nine on screen; shown in INSERT too, so it can be
// read ahead.
Rectangle {
    id: root

    property int index: -1
    property var shown: ({ first: 0, end: 0 })
    readonly property string digit: BrowseLayout.hint_of(root.index, root.shown)

    visible: root.digit !== ""
    width: Math.max(height, digit_text.implicitWidth + 6)
    height: digit_text.implicitHeight + 2
    radius: Style.radius(3)
    color: Qt.alpha(Theme.bg_surface, 0.9)

    Text {
        id: digit_text
        anchors.centerIn: parent
        text: root.digit
        color: Style.text_muted
        font.family: Style.font_family
        font.pixelSize: Style.fs(-5)
        font.bold: true
    }
}
