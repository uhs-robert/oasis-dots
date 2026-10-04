// home/quickshell/.config/quickshell/picker/hyprvim/CompletionMenu.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../components"
import "../../theme"
import "../Fuzzy.js" as Fuzzy

// Fixed slots over a window of items: typing rebinds rows instead of recreating them.
Column {
    id: root

    property var st
    property var items: []
    property int menu_top: 0
    property int menu_rows: 0
    property int menu_slots: 0
    property bool built: false
    property int selected: -1
    property bool usage_column: false
    property real row_height: 0

    signal picked(int i)
    signal scrolled(int d)

    readonly property real label_width: Math.max(Style.px(160), root.width * 0.3)
    readonly property bool usage_wide: root.width >= Style.px(720)
    readonly property real usage_width: !root.usage_column ? 0 : root.usage_wide ? Math.max(Style.px(150), root.width * 0.2) : Style.px(14)

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root.scrolled(event.angleDelta.y < 0 ? 1 : -1)
    }

    Repeater {
        model: root.built ? root.menu_slots : 0

        delegate: Item {
            id: menu_slot
            required property int index
            width: root.width
            height: root.row_height
            visible: menu_slot.index < root.menu_rows

            MenuRow {
                id: row
                readonly property int item_index: root.menu_top + menu_slot.index
                readonly property var entry: root.items[row.item_index] || ({ item: { label: "", description: "" }, positions: [] })

                width: root.width
                height: root.row_height - 2
                selected: row.item_index === root.selected

                Text {
                    id: row_label
                    x: 8 + row.inset
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.label_width)
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: Fuzzy.highlight(row.entry.item.label, row.entry.positions, String(row.fg(root.st.text_accent)))
                    color: row.fg(root.st.text_fg)
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-1)
                }

                Text {
                    x: 8 + row.inset + root.label_width + 16
                    width: root.usage_width
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.usage_width > 0 && !!row.entry.item.usage
                    elide: Text.ElideRight
                    text: root.usage_wide ? row.entry.item.usage || "" : "…"
                    color: row.fg(root.st.text_muted)
                    opacity: 0.7
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-3)
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 8 + row.inset + root.label_width + 16 + (root.usage_width > 0 ? root.usage_width + 12 : 0)
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: row.entry.item.description
                    color: row.fg(root.st.text_muted)
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-3)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.picked(row.item_index)
                }
            }
        }
    }
}
