// home/quickshell/.config/quickshell/components/RowLabel.qml
import QtQuick
import "../theme"
import "Search.js" as Search

// A row's label text; the enclosing popup's `/` query is underlined in it.
Text {
    id: root

    readonly property var st: Style.for_item(root)

    property string label: ""
    property bool searchable: true
    readonly property var popup: {
        for (let p = root.parent; p; p = p.parent) {
            if (p.search_popup !== undefined) return p.search_popup;
        }
        return null;
    }
    readonly property string query: root.searchable && root.popup && root.popup.search_shown ? root.popup.search_query : ""
    // Inverse selections repaint the row in one color; the mark keeps it and relies on the underline.
    readonly property color mark_color: root.st.selection_inverse && Qt.colorEqual(root.color, root.st.selection_fg) ? root.color : root.st.caret_color
    readonly property var marked: root.query !== "" ? Search.mark(root.label, root.query, root.mark_color) : null

    textFormat: root.marked !== null ? Text.StyledText : Text.PlainText
    text: root.marked !== null ? root.marked : root.label
}
