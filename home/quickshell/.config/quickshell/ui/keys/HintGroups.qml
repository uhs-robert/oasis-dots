import QtQuick
import qs.theme
import "KeyHints.js" as KeyHints

// The key groups of a hint bar: one column per group, a small heading over its [cap, label] keys, so a wrap never splits
// a group. One row while it fits in max_width, then it wraps whole groups onto the next row.
Flow {
    id: root
    // [{ name, keys: [[cap, label]...] }...]
    property var groups: []
    property real max_width: Infinity
    // The widest row once the groups are filled in the way Flow fills them, so a wrapped bar is no wider than its rows.
    readonly property real fitted_width: root.fill(root.max_width).width
    width: root.fitted_width
    spacing: 18

    // How Flow fills `width` with the groups: { rows, width } with width the widest row. Lets a caller compare layouts
    // before choosing one.
    function fill(width) {
        let line = 0, widest = 0, rows = 0;
        for (let i = 0; i < groups_repeater.count; i++) {
            const item = groups_repeater.itemAt(i);
            if (!item) continue;
            if (line > 0 && line + root.spacing + item.implicitWidth > width) {
                widest = Math.max(widest, line);
                line = item.implicitWidth;
                rows++;
            } else {
                if (line === 0) rows = Math.max(rows, 1);
                line += (line > 0 ? root.spacing : 0) + item.implicitWidth;
            }
        }
        return { rows: rows, width: Math.ceil(Math.max(widest, line)) };
    }

    Repeater {
        id: groups_repeater
        model: root.groups
        Column {
            id: col
            required property var modelData
            spacing: 4
            Text {
                text: col.modelData.name.toUpperCase()
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
                font.letterSpacing: 1.5
            }
            Rectangle {
                width: parent.width
                height: 1
                color: Style.accent_color
                opacity: 0.6
            }
            Row {
                spacing: 12
                Repeater {
                    model: col.modelData.keys
                    Row {
                        id: item
                        required property var modelData
                        spacing: 4
                        Text {
                            text: KeyHints.with_glyphs(item.modelData[0])
                            color: Style.accent_color
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                            font.bold: true
                        }
                        Text {
                            text: item.modelData[1]
                            color: Style.text_fg
                            font.family: Style.font_family
                            font.pixelSize: Style.fs(-1)
                        }
                    }
                }
            }
        }
    }
}
