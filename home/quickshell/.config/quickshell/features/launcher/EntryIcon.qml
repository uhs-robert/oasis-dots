import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.theme

// A picker item's icon in a 20 px square, or its text glyph (an emoji, a Nerd Font symbol) in place of one.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property var entry: ({})
    // The glyph's font when the item names none.
    property string glyph_font: root.st.font_family
    property real glyph_px: root.st.fs(2)
    property color glyph_color: root.st.text_fg
    // A card hangs its glyph from the square's top edge; a row centres it on the square.
    property bool glyph_on_top: false

    width: Style.px(20)
    height: Style.px(20)

    function icon_source(item) {
        if (item.icon_path !== undefined) return item.icon_path;
        const icon = item.icon;
        if (!icon) return Quickshell.iconPath("application-x-executable", true);
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, "application-x-executable");
    }

    IconImage {
        visible: !root.entry.glyph
        implicitSize: Style.px(20)
        asynchronous: true
        source: root.entry.glyph ? "" : root.icon_source(root.entry)
    }

    Text {
        visible: !!root.entry.glyph
        anchors.verticalCenter: root.glyph_on_top ? undefined : parent.verticalCenter
        width: Style.px(20)
        horizontalAlignment: Text.AlignHCenter
        text: root.entry.glyph || ""
        textFormat: Text.PlainText
        color: root.glyph_color
        font.family: root.entry.glyph_font || root.glyph_font
        font.weight: root.entry.glyph_weight || Font.Normal
        font.pixelSize: root.glyph_px
    }
}
