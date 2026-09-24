// home/quickshell/.config/quickshell/bar/modules/Keeptabs.qml
import QtQuick
import Quickshell
import "../../theme"
import "../../services"

Item {
    id: root

    property bool compact: false
    property string screen_name: ""
    property Item island: null
    property color island_color: Theme.bg_core

    readonly property bool shown: KeeptabsState.available
    readonly property string tooltip_text: {
        const usage = ClaudeUsageState.rows.map(r => r.label + ": " + r.percent + "%").join("\n");
        return KeeptabsState.tooltip.replace(/\t/g, "  ") + (usage ? "\n\n" + usage : "");
    }
    visible: shown
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    onIslandChanged: if (root.island) Popups.register_default("keeptabs", root.island, root.island_color, root.screen_name, root)
    Component.onDestruction: Popups.unregister("keeptabs", root.screen_name, root)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Style.bar_radius(4)
        color: Style.bar_hover_bg
        opacity: hover_handler.hovered ? 0.5 : 0
    }

    // Folds keeptabs' "glyph count" runs into {glyph, count} groups so the count can sit as a badge.
    readonly property var groups: {
        const out = [];
        for (const r of KeeptabsState.runs) {
            const text = r.text;
            const both = /^\s*(\S+)\s+(\d+)\s*$/.exec(text);
            const count_only = /^\s*(\d+)\s*$/.exec(text);
            if (both) out.push({ glyph: both[1], count: both[2], color: r.color, rise: r.rise });
            else if (count_only && out.length) out[out.length - 1].count = count_only[1];
            else if (/^\s+$/.test(text)) continue;
            else out.push({ glyph: text.trim(), count: "", color: r.color, rise: r.rise });
        }
        return out;
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            model: root.groups

            Item {
                id: group
                required property var modelData

                implicitWidth: glyph_text.implicitWidth + (count_text.visible ? count_text.implicitWidth * 0.6 : 0)
                implicitHeight: glyph_text.implicitHeight

                Text {
                    id: glyph_text
                    // Pango rise is in 1/1024 pt; keeptabs uses +-1024 to bob the running icon.
                    y: -group.modelData.rise / 1024
                    text: group.modelData.glyph
                    color: group.modelData.color || Theme.theme_primary
                    font.family: Style.bar_font_family
                    style: Style.bar_text_style
                    styleColor: Style.bar_glow_color
                    font.pixelSize: Theme.glyph_size
                }

                Text {
                    id: count_text
                    visible: group.modelData.count !== ""
                    x: glyph_text.implicitWidth - implicitWidth * 0.4
                    y: -3
                    text: group.modelData.count
                    color: group.modelData.color || Theme.theme_primary
                    font.family: Style.bar_font_family
                    style: Style.bar_text_style
                    styleColor: Style.bar_glow_color
                    font.pixelSize: Style.bar_font_size - 3
                    font.bold: true
                }
            }
        }
    }

    HoverHandler {
        id: hover_handler
        onHoveredChanged: {
            if (hovered) Tooltip.show(root, root.tooltip_text, "keeptabs");
            else Tooltip.hide(root);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.toggle("keeptabs", root.island, root.island_color, root.screen_name)
    }
}
