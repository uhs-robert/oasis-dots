pragma ComponentBehavior: Bound
import QtQuick
import qs.theme
import "AnsiText.js" as AnsiText
import "TmuxLayout.js" as TmuxLayout

// A tmux window as its terminal shows it: the window's whole cell grid, scaled to fit and centred, with every pane at its
// place and tmux's borders between them. The text is in the terminal's font and colours. The pane `[`/`]` chose has a
// primary-coloured outline when the window has more than one.
Item {
    id: root

    property var entry: null
    // The pane Enter lands on.
    property var shown: null
    // pane id -> its captured lines with their colour codes.
    property var captures: ({})

    readonly property var panes: TmuxLayout.drawn_panes(root.entry, root.shown)
    readonly property var grid_size: TmuxLayout.grid_size(root.entry)
    // The theme's font, which the terminal uses too: Style.mono_font follows the bar style, the terminal does not.
    readonly property string font_family: Theme.font_family
    readonly property int font_px: TmuxLayout.font_px_to_fit(root.grid_size.cols, root.grid_size.rows, root.width, root.height, reference_metrics.font.family !== "" ? reference_metrics.advanceWidth("M") / 100 : 0, reference_metrics.lineSpacing / 100)
    // advanceWidth is a call, so the binding reads the font to rerun when it changes.
    readonly property real cell_w: metrics.font.pixelSize > 0 ? metrics.advanceWidth("M") : 0
    readonly property real cell_h: metrics.lineSpacing
    readonly property var box: TmuxLayout.letterbox(Math.ceil(root.grid_size.cols * root.cell_w), Math.ceil(root.grid_size.rows * root.cell_h), root.width, root.height)
    // The terminal's colours, from the raw palette: a style remaps Style.pal, the terminal does not follow it.
    readonly property var ansi_palette: [Theme.black, Theme.red, Theme.green, Theme.yellow, Theme.blue, Theme.magenta, Theme.cyan, Theme.white, Theme.bright_black, Theme.bright_red, Theme.bright_green, Theme.bright_yellow, Theme.bright_blue, Theme.bright_magenta, Theme.bright_cyan, Theme.bright_white].map(AnsiText.hex_of)
    readonly property string fg_hex: AnsiText.hex_of(Theme.fg_core)
    readonly property string bg_hex: AnsiText.hex_of(Theme.bg_core)

    FontMetrics {
        id: reference_metrics
        font.family: root.font_family
        font.pixelSize: 100
    }

    FontMetrics {
        id: metrics
        font.family: root.font_family
        font.pixelSize: Math.max(1, root.font_px)
    }

    Rectangle {
        id: grid
        visible: root.font_px > 0
        x: root.box.x
        y: root.box.y
        width: root.box.w
        height: root.box.h
        color: Theme.bg_core
        clip: true

        Repeater {
            model: root.panes

            Text {
                required property var modelData
                x: modelData.x * root.cell_w
                y: modelData.y * root.cell_h
                width: modelData.w * root.cell_w
                height: modelData.h * root.cell_h
                clip: true
                text: AnsiText.to_rich(TmuxLayout.screen_text(root.captures[modelData.pane_id], modelData.h), root.fg_hex, root.ansi_palette, root.bg_hex)
                textFormat: Text.RichText
                wrapMode: Text.NoWrap
                lineHeightMode: Text.FixedHeight
                lineHeight: root.cell_h
                color: Theme.fg_core
                font.family: root.font_family
                font.pixelSize: root.font_px
            }
        }

        Repeater {
            model: TmuxLayout.borders(root.panes, root.grid_size.cols, root.grid_size.rows)

            Rectangle {
                required property var modelData
                x: Math.round(modelData.x1 * root.cell_w)
                y: Math.round(modelData.y1 * root.cell_h)
                width: Math.max(1, Math.round((modelData.x2 - modelData.x1) * root.cell_w))
                height: Math.max(1, Math.round((modelData.y2 - modelData.y1) * root.cell_h))
                color: Theme.bright_black
            }
        }

        Rectangle {
            readonly property var outline: root.shown ? TmuxLayout.frame(root.panes.find(p => p.pane_id === root.shown.pane_id) || { x: 0, y: 0, w: 0, h: 0 }, root.grid_size.cols, root.grid_size.rows) : null
            visible: root.panes.length > 1 && !!outline
            x: outline ? Math.round(outline.x * root.cell_w) - 1 : 0
            y: outline ? Math.round(outline.y * root.cell_h) - 1 : 0
            width: outline ? Math.round(outline.w * root.cell_w) + 2 : 0
            height: outline ? Math.round(outline.h * root.cell_h) + 2 : 0
            color: "transparent"
            border.width: 2
            border.color: Theme.theme_primary
        }
    }

    // The terminal window's edge, where the grid meets the letterbox.
    Rectangle {
        visible: grid.visible
        x: grid.x - 1
        y: grid.y - 1
        width: grid.width + 2
        height: grid.height + 2
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Theme.ui_border, 0.8)
    }
}
