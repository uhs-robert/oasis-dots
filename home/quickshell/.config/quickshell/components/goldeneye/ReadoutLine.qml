// home/quickshell/.config/quickshell/components/goldeneye/ReadoutLine.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../theme/Watch.js" as W

// A caps label over a value in the watch's fonts: digits in seven-segment, the rest in Share Tech Mono, long text elided.
ColumnLayout {
    id: root

    property string label: ""
    property string digits: ""
    property string unit: ""
    property string text: ""
    property color tone: Style.wk.lit
    property bool alert: false
    spacing: 1

    Text {
        text: root.label
        color: root.alert ? Style.pal.error : Style.wk.soft
        font.family: W.head_font
        font.pixelSize: Style.fs(-7)
        font.letterSpacing: 1
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 5

        Text {
            visible: root.digits !== ""
            text: root.digits
            color: root.tone
            font.family: W.digit_font
            font.pixelSize: Style.fs(2)
        }

        Text {
            visible: root.unit !== ""
            text: root.unit
            color: root.tone
            font.family: W.mono_font
            font.pixelSize: Style.fs(-2)
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: root.text !== ""
            elide: Text.ElideRight
            text: root.text
            color: root.tone
            font.family: W.mono_font
            font.pixelSize: Style.fs(-2)
        }
    }
}
