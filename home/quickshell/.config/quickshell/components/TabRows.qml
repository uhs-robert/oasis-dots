// home/quickshell/.config/quickshell/components/TabRows.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../theme"

// A row of MenuTabs sized to their labels that wraps into balanced rows when one row cannot hold them; `chips` centers pill chips instead.
ColumnLayout {
    id: root

    readonly property var st: Style.for_item(root)

    property var labels: []
    property int current: 0
    property bool chips: false
    property int font_size: root.chips ? root.st.font_size - 3 : root.st.font_size - 2
    property real tab_height: Style.px(24)
    // Other label sets this row switches between; the tallest reserves the height so switching never resizes.
    property var reserve_labels: []

    signal picked(int index)

    spacing: 4
    Layout.preferredHeight: root.row_count > 0 ? root.row_count * root.tab_height + (root.row_count - 1) * root.spacing : 0

    FontMetrics {
        id: label_metrics
        font.family: root.st.font_family
        font.pixelSize: root.font_size
        font.bold: true
        font.capitalization: root.st.tab_caps ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.st.tab_caps ? root.st.label_spacing : 0
    }

    FontMetrics {
        id: key_metrics
        font.family: root.st.font_family
        font.pixelSize: root.st.font_size - 5
        font.bold: true
    }

    // Mirrors MenuTab and KeyBadge sizing so rows can be split before the tabs exist.
    readonly property real key_space: root.st.tab_keys && !root.chips ? Math.max(key_metrics.height + 2, key_metrics.advanceWidth("9") + 8) + root.st.slant * (key_metrics.height + 2) + 6 : 0

    function needs(list) {
        // Reading .font re-runs dependent bindings when the style changes the font.
        const f = label_metrics.font;
        return list.map(l => root.chips ? label_metrics.advanceWidth(root.st.chip_brackets ? "[" + l + "]" : l) + 20 : label_metrics.advanceWidth(l) + 12 + root.key_space);
    }

    // Fewest balanced rows of consecutive indices whose widths fit `avail`.
    function split(widths, avail) {
        const n = widths.length;
        for (let r = 1; r <= n; r++) {
            const per = Math.ceil(n / r);
            const rows = [];
            let fits = true;
            for (let i = 0; i < n; i += per) {
                const idx = [];
                let w = -root.spacing;
                for (let j = i; j < Math.min(n, i + per); j++) {
                    idx.push(j);
                    w += widths[j] + root.spacing;
                }
                if (w > avail) fits = false;
                rows.push(idx);
            }
            if (fits || per === 1) return rows;
        }
        return [];
    }

    readonly property var label_needs: root.needs(root.labels)
    readonly property var rows: root.split(root.label_needs, root.width)
    readonly property int row_count: Math.max(root.rows.length, ...root.reserve_labels.map(l => root.split(root.needs(l), root.width).length))

    Repeater {
        model: root.rows

        RowLayout {
            id: tab_row
            required property var modelData

            Layout.fillWidth: !root.chips
            Layout.alignment: Qt.AlignHCenter
            spacing: root.spacing

            Repeater {
                model: tab_row.modelData

                MenuTab {
                    id: tab
                    required property int modelData

                    Layout.fillWidth: !root.chips
                    Layout.preferredWidth: root.chips ? -1 : root.label_needs[tab.modelData] || 0
                    implicitHeight: root.tab_height
                    base_radius: root.chips ? 12 : 4
                    font_size: root.font_size
                    label: root.labels[tab.modelData] || ""
                    active: tab.modelData === root.current
                    key: root.chips || tab.modelData >= 9 ? "" : String(tab.modelData + 1)
                    onClicked: root.picked(tab.modelData)
                }
            }
        }
    }
}
