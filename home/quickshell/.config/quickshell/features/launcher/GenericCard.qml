import QtQuick
import qs.theme
import "../../core/Fuzzy.js" as Fuzzy

// A browse card for a provider with no `card` of its own: icon and label, the description wrapped under them.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property var entry: ({})
    property var positions: []
    property bool selected: false
    property string glyph_font: root.st.font_family

    EntryIcon {
        id: icon
        entry: root.entry
        glyph_font: root.glyph_font
        glyph_on_top: true
    }

    Text {
        anchors.left: icon.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.verticalCenter: icon.verticalCenter
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: Fuzzy.highlight(root.entry.label || "", root.positions, String(root.st.text_accent))
        color: root.entry.accent ? root.st.text_accent : root.st.text_fg
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-1)
    }

    Text {
        anchors.top: icon.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        text: root.entry.description || ""
        textFormat: Text.PlainText
        color: root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
