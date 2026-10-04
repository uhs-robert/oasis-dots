// home/quickshell/.config/quickshell/tmux_overview/TmuxTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../components"
import "../theme"

// One tmux window as a small terminal: its panes at their real places, each showing its last captured text.
Item {
    id: root

    property var entry: null
    property bool selected: false
    property string selected_pane: ""
    property bool picked: false
    // 1-based mark number, 0 when unmarked.
    property int mark: 0
    property bool swap_target: false
    property bool drop_target: false
    property bool dimmed: false
    // pane_id -> rich text from Ansi.js.
    property var previews: ({})
    property bool shown: true

    readonly property var panes: root.entry ? root.entry.panes : []
    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color text_glow: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow
    readonly property real label_px: Math.max(9, Math.min(Style.fs(-3), root.height * 0.16))
    readonly property real ref_px: 10
    readonly property real min_row_px: 4

    signal pane_clicked(string pane_id)
    signal tile_clicked()

    FontMetrics {
        id: metrics
        font.family: Style.mono_font
        font.pixelSize: root.ref_px
    }

    Rectangle {
        anchors.fill: parent
        radius: Style.radius(6)
        color: root.selected ? Qt.tint(Theme.bg_crust, Qt.alpha(Style.caret_color, 0.08)) : Theme.bg_crust
        border.width: root.selected ? 2 : 1
        border.color: root.drop_target || root.swap_target ? Style.text_accent : root.selected ? Style.caret_color : Theme.ui_border
        opacity: root.picked ? 0.45 : root.dimmed ? 0.2 : 1
    }

    Dither {
        visible: color.a > 0
        anchors.fill: parent
        anchors.margins: 1
        color: Style.dither
        radius: Style.radius(6)
        top_radius: Style.radius(6)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.tile_clicked()
    }

    Item {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2
        opacity: root.picked ? 0.45 : root.dimmed ? 0.2 : 1
        clip: true

        Repeater {
            model: root.panes

            Rectangle {
                id: pane
                required property var modelData
                readonly property bool is_selected: root.selected && pane.modelData.pane_id === root.selected_pane
                readonly property string html: root.previews[pane.modelData.pane_id] || ""
                readonly property bool readable: root.selected || (pane.height - pane.border.width * 2) / Math.max(1, pane.modelData.rows) >= root.min_row_px

                x: Math.round(pane.modelData.rx * canvas.width)
                y: Math.round(pane.modelData.ry * canvas.height)
                width: Math.max(4, Math.round(pane.modelData.rw * canvas.width))
                height: Math.max(4, Math.round(pane.modelData.rh * canvas.height))
                z: pane.is_selected ? 10 : 0
                color: Theme.bg_core
                radius: Style.radius(2)
                border.width: pane.is_selected ? 2 : 1
                border.color: pane.is_selected ? Style.caret_color : Qt.alpha(Theme.ui_border, 0.8)
                clip: true

                Loader {
                    active: root.shown && pane.html !== "" && pane.readable
                    x: pane.border.width
                    y: pane.border.width
                    width: pane.modelData.cols * metrics.averageCharacterWidth
                    height: pane.modelData.rows * metrics.lineSpacing
                    transform: Scale {
                        xScale: (pane.width - pane.border.width * 2) / Math.max(1, pane.modelData.cols * metrics.averageCharacterWidth)
                        yScale: (pane.height - pane.border.width * 2) / Math.max(1, pane.modelData.rows * metrics.lineSpacing)
                    }

                    sourceComponent: Text {
                        text: "<div style=\"white-space:pre\">" + pane.html + "</div>"
                        textFormat: Text.RichText
                        color: Theme.fg_core
                        font.family: Style.mono_font
                        font.pixelSize: root.ref_px
                    }
                }

                Text {
                    visible: root.shown && pane.html !== "" && !pane.readable && pane.height >= 12 && pane.width >= 24
                    anchors.centerIn: parent
                    width: pane.width - 6
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: pane.modelData.cmd
                    color: Qt.alpha(Theme.fg_core, 0.5)
                    font.family: Style.mono_font
                    font.pixelSize: 9
                }

                CornerBrackets {
                    anchors.fill: parent
                    visible: pane.is_selected && color.a > 0
                    color: Style.selection_brackets
                    inset: 2
                    arm: Math.min(10, pane.width / 4)
                    all_corners: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.pane_clicked(pane.modelData.pane_id)
                }
            }
        }
    }

    Rectangle {
        id: label_chip
        x: 4
        y: 4
        z: 20
        width: Math.min(root.width - 8, label_text.implicitWidth + 10)
        height: label_text.implicitHeight + 2
        radius: Style.radius(3)
        visible: root.height >= 28
        color: root.selected ? Style.caret_color : Qt.alpha(Theme.bg_crust, 0.85)

        Text {
            id: label_text
            anchors.centerIn: parent
            width: parent.width - 10
            elide: Text.ElideRight
            text: root.entry ? root.entry.index + " " + root.entry.name.trim() + (root.entry.cmd !== "" ? " · " + root.entry.cmd : "") : ""
            color: root.selected ? Theme.bg_crust : root.entry && root.entry.active ? Style.text_accent : Style.text_primary
            font.family: Style.font_family
            font.pixelSize: root.label_px
            font.bold: true
            style: root.selected ? Text.Normal : root.text_style
            styleColor: root.text_glow
        }
    }

    Rectangle {
        visible: root.mark > 0 && root.height >= 16
        x: root.width - width - 4
        y: 4
        z: 20
        width: Math.max(height, mark_text.implicitWidth + 8)
        height: mark_text.implicitHeight + 2
        radius: Style.radius(height / 2)
        color: Style.text_accent

        Text {
            id: mark_text
            anchors.centerIn: parent
            text: "✓" + root.mark
            color: Theme.bg_crust
            font.family: Style.font_family
            font.pixelSize: root.label_px
            font.bold: true
        }
    }

    Rectangle {
        visible: root.swap_target && root.height >= 20
        anchors.centerIn: parent
        z: 20
        width: swap_text.implicitWidth + 10
        height: swap_text.implicitHeight + 2
        radius: Style.radius(3)
        color: Style.text_accent

        Text {
            id: swap_text
            anchors.centerIn: parent
            text: "SWAP"
            color: Theme.bg_crust
            font.family: Style.font_family
            font.pixelSize: root.label_px
            font.bold: true
        }
    }
}
