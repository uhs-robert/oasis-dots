pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.components
import qs.ui.effects
import qs.ui.frames
import qs.theme
import qs.features.windows
import "Layout.js" as Layout

// One workspace as a small monitor: its windows at their real places, scaled into the tile.
Item {
    id: root

    property var entry: null
    property bool selected: false
    property string selected_address: ""
    // Carried windows (address -> true), the first one's toplevel for the drop icon, and how many there are.
    property var picked: ({})
    property var picked_toplevel: null
    property int picked_count: 0
    // Marked windows: address -> 1-based mark number.
    property var marks: ({})
    property string swap_address: ""
    property bool drop_target: false
    // Voice numbers: address -> number, drawn on every window while show_numbers is on.
    property var numbers: ({})
    property bool show_numbers: false
    // Addresses kept bright by the filter; null while nothing is typed.
    property var matches: null
    // Windows capture continuously; otherwise each shows one frame taken as it appears.
    property bool live: false
    property int live_cap: 6
    property bool shown: true

    readonly property bool is_new: !!root.entry && root.entry.is_new
    readonly property var windows: root.entry ? root.entry.windows : []
    // address -> { info, order }; delegates live per address so thumbnails outlive rebuilt entries.
    readonly property var window_map: {
        const out = {};
        root.windows.forEach((w, i) => out[w.address] = { info: w, order: i });
        return out;
    }

    onWindowsChanged: Layout.sync_keys(slots, root.windows.map(w => w.address))
    Component.onCompleted: Layout.sync_keys(slots, root.windows.map(w => w.address))

    ListModel {
        id: slots
    }
    readonly property int text_style: Style.glow ? Text.Outline : Style.text_shadow.a > 0 ? Text.Raised : Text.Normal
    readonly property color text_glow: Style.glow ? Qt.alpha(Theme.theme_primary, 0.3) : Style.text_shadow
    // nf-fa-window_maximize, in the Nerd Font symbols face the bar already uses for glyphs.
    readonly property string window_glyph: "\uf2d0"
    // Voice mode reads a workspace as "WS 3"; special workspaces keep their name.
    readonly property string label: {
        const name = root.entry ? root.entry.name : "";
        if (root.is_new) return "+ " + name;
        return root.show_numbers && /^\d+$/.test(name) ? "WS " + name : name;
    }
    // Game Boy's caret is the crust shade (Color) or a tint of it (Original), so the selected chip's dark text would
    // vanish on its fill; below this lightness gap it takes the style's inverse selection pair instead.
    readonly property bool chip_low_contrast: Math.abs(Style.caret_color.hslLightness - Theme.bg_crust.hslLightness) < 0.3
    readonly property color chip_fill: root.chip_low_contrast ? Style.selection_bg : Style.caret_color
    readonly property color chip_text: root.chip_low_contrast ? Style.selection_fg : Theme.bg_crust
    readonly property real label_px: Math.max(9, Math.min(Style.fs(-3), root.height * 0.16))

    signal window_clicked(string address)
    signal tile_clicked()

    Rectangle {
        anchors.fill: parent
        radius: Style.radius(6)
        color: root.is_new ? "transparent" : root.selected ? Qt.tint(Theme.bg_crust, Qt.alpha(Style.caret_color, 0.08)) : Theme.bg_crust
        border.width: root.is_new ? 0 : root.selected ? 2 : 1
        border.color: root.drop_target ? Style.text_accent : root.selected ? Style.caret_color : Theme.ui_border
    }

    Dither {
        visible: !root.is_new && color.a > 0
        anchors.fill: parent
        anchors.margins: 1
        color: Style.dither
        radius: Style.radius(6)
        top_radius: Style.radius(6)
    }

    DashedOutline {
        visible: root.is_new
        anchors.fill: parent
        color: root.drop_target ? Style.text_accent : root.selected ? Style.caret_color : Theme.ui_border
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.tile_clicked()
    }

    Item {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2
        clip: true

        Repeater {
            model: slots

            Rectangle {
                id: win
                required property string key
                readonly property var slot: root.window_map[win.key] || ({ info: { address: win.key, toplevel: null, rx: 0, ry: 0, rw: 0, rh: 0, floating: false }, order: 0 })
                readonly property var modelData: win.slot.info
                readonly property int index: win.slot.order
                readonly property bool is_selected: root.selected && win.modelData.address === root.selected_address
                readonly property bool is_picked: !!root.picked[win.modelData.address]
                readonly property int mark: root.marks[win.modelData.address] || 0
                readonly property int voice_n: root.numbers[win.modelData.address] || 0
                readonly property bool is_swap: win.modelData.address === root.swap_address
                readonly property bool dimmed: root.matches !== null && !root.matches[win.modelData.address]

                x: win.modelData.rx * canvas.width
                y: win.modelData.ry * canvas.height
                width: Math.max(4, win.modelData.rw * canvas.width)
                height: Math.max(4, win.modelData.rh * canvas.height)
                z: win.is_selected ? 100 : win.modelData.floating ? 50 + win.index : win.index
                color: Theme.bg_surface
                radius: Style.radius(3)
                border.width: win.is_selected || win.mark > 0 || win.is_swap ? 2 : 1
                border.color: win.is_picked || win.is_swap || (win.mark > 0 && !win.is_selected) ? Style.text_accent : win.is_selected ? Style.caret_color : Qt.alpha(Theme.ui_border, 0.8)
                opacity: win.is_picked ? 0.45 : win.dimmed ? 0.2 : 1
                clip: true

                WindowThumbnail {
                    anchors.fill: parent
                    anchors.margins: win.border.width
                    toplevel: win.modelData.toplevel
                    tint: Style.overview_skin === "goldeneye" && !win.is_selected
                    active: root.shown
                    live: root.live && win.index < root.live_cap
                    icon_size: Math.min(width, height) * 0.45
                }

                CornerBrackets {
                    anchors.fill: parent
                    visible: win.is_selected && color.a > 0
                    color: Style.selection_brackets
                    inset: 2
                    arm: Math.min(10, win.width / 4)
                    all_corners: true
                }

                DashedOutline {
                    visible: win.is_swap
                    anchors.fill: parent
                    anchors.margins: 4
                    color: Style.text_accent
                }

                Rectangle {
                    visible: win.is_swap && win.height >= 20
                    anchors.centerIn: parent
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

                // Bottom left: the workspace label chip sits at the tile's top left and the mark check at the window's top right.
                // The text shrinks with the window so a small window or a two-digit number is never cut off at its edges.
                Rectangle {
                    // Glyph and digits are laid out as one run of characters, the glyph counted as one wide character.
                    readonly property real number_px: Math.max(7, Math.min(root.label_px, win.height * 0.28, (win.width - 10) / (0.75 * (number_text.text.length + 1.5))))
                    visible: root.show_numbers && win.voice_n > 0 && win.height >= 10 && win.width >= 12
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 3
                    width: Math.max(height, number_row.implicitWidth + 6)
                    height: number_row.implicitHeight + 2
                    radius: Style.radius(3)
                    color: Theme.bg_crust
                    border.width: 1
                    border.color: Style.text_accent

                    Row {
                        id: number_row
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.window_glyph
                            color: Style.text_accent
                            font.family: "Symbols Nerd Font"
                            font.pixelSize: parent.parent.number_px
                        }

                        Text {
                            id: number_text
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(win.voice_n)
                            color: Style.text_accent
                            font.family: Style.font_family
                            font.pixelSize: parent.parent.number_px
                            font.bold: true
                        }
                    }
                }

                // While voice numbers show, the check stands alone: the mark order would be a second number on the window.
                Rectangle {
                    visible: win.mark > 0 && win.height >= 16
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 3
                    width: Math.max(height, mark_text.implicitWidth + 8)
                    height: mark_text.implicitHeight + 2
                    radius: Style.radius(height / 2)
                    color: Style.text_accent

                    Text {
                        id: mark_text
                        anchors.centerIn: parent
                        text: "\u2713" + (root.show_numbers ? "" : win.mark)
                        color: Theme.bg_crust
                        font.family: Style.font_family
                        font.pixelSize: Math.min(root.label_px, win.height * 0.28)
                        font.bold: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.window_clicked(win.modelData.address)
                }
            }
        }
    }

    Rectangle {
        id: label_chip
        x: 4
        y: 4
        width: label_text.implicitWidth + 10
        height: label_text.implicitHeight + 2
        radius: Style.radius(3)
        visible: root.height >= 28
        color: root.selected ? root.chip_fill : Qt.alpha(Theme.bg_crust, 0.85)

        Text {
            id: label_text
            anchors.centerIn: parent
            text: root.label
            color: root.selected ? root.chip_text : root.entry && root.entry.focused ? Style.text_accent : root.entry && root.entry.shown_on_monitor ? Style.text_primary : Style.text_muted
            font.family: Style.font_family
            font.pixelSize: root.label_px
            font.bold: true
            style: root.selected ? Text.Normal : root.text_style
            styleColor: root.text_glow
        }
    }

    // The window being carried, shown where it would land.
    IconImage {
        visible: root.drop_target && !!root.picked_toplevel
        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height) * 0.35
        opacity: 0.8
        asynchronous: true
        source: root.picked_toplevel ? WindowState.icon_for(root.picked_toplevel) : ""

        Rectangle {
            visible: root.picked_count > 1
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(height, count_text.implicitWidth + 8)
            height: count_text.implicitHeight + 2
            radius: Style.radius(height / 2)
            color: Style.text_accent

            Text {
                id: count_text
                anchors.centerIn: parent
                text: String(root.picked_count)
                color: Theme.bg_crust
                font.family: Style.font_family
                font.pixelSize: root.label_px
                font.bold: true
            }
        }
    }
}
