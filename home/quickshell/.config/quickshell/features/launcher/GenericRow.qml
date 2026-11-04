import QtQuick
import qs.theme
import "../../core/Fuzzy.js" as Fuzzy

// A browse list row for a provider with no `row` of its own: icon, label, then the description.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property var entry: ({})
    property var positions: []
    property bool selected: false
    property string glyph_font: root.st.font_family

    EntryIcon {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        entry: root.entry
        glyph_font: root.glyph_font
        glyph_px: root.st.fs(1)
    }

    Text {
        id: label
        anchors.left: icon.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.6)
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: Fuzzy.highlight(root.entry.label || "", root.positions, String(root.st.text_accent))
        color: root.entry.accent ? root.st.text_accent : root.st.text_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-1)
    }

    Text {
        anchors.left: label.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: root.entry.description || ""
        textFormat: Text.PlainText
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
