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
    readonly property bool pills: root.chips && !root.st.chip_tabs
    property int font_size: root.chips ? root.st.fs(-3) : root.st.fs(-2)
    property real tab_height: Style.px(24)
    // Other label sets this row switches between; the tallest reserves the height so switching never resizes.
    property var reserve_labels: []

    signal picked(int index)

    // Room between a row and the edge of its well, in styles with a tab_well.
    readonly property real well_pad: root.st.tab_well.a > 0 ? 3 : 0
    readonly property real row_height: root.tab_height + root.well_pad * 2

    spacing: 4
    Layout.preferredHeight: root.row_count > 0 ? root.row_count * root.row_height + (root.row_count - 1) * root.spacing : 0

    FontMetrics {
        id: label_metrics
        font.family: root.st.label_font_family
        font.pixelSize: root.font_size
        font.bold: true
        font.capitalization: root.st.tab_caps || root.st.caps_tracking > 0 ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.st.caps_tracking > 0 ? root.st.caps_tracking * (root.chips ? 0.3 : 1) : root.st.tab_caps ? root.st.label_spacing : 0
    }

    FontMetrics {
        id: key_metrics
        font.family: root.st.mono_font
        font.pixelSize: root.st.fs(-5)
        font.bold: root.st.mono_font === root.st.font_family
    }

    // Mirrors MenuTab and KeyBadge sizing so rows can be split before the tabs exist.
    readonly property real key_space: root.st.tab_keys && !root.chips ? Math.max(key_metrics.height + 2, key_metrics.advanceWidth("9") + 8) + 6 : 0

    readonly property real bracket_space: root.st.tab_brackets.a > 0 && !root.chips ? label_metrics.advanceWidth("[]") + 4 : 0

    function needs(list) {
        // Reading .font re-runs dependent bindings when the style changes the font.
        const f = label_metrics.font;
        const hand = root.st.hand_cursor ? 20 : 0;
        return list.map(l => root.pills ? label_metrics.advanceWidth(root.st.chip_brackets ? "[" + l + "]" : l) + 20 + hand : label_metrics.advanceWidth(l) + 12 + root.key_space + root.bracket_space + hand);
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
    readonly property real row_room: root.width - root.well_pad * 2
    readonly property var rows: root.split(root.label_needs, root.row_room)
    readonly property int row_count: Math.max(root.rows.length, ...root.reserve_labels.map(l => root.split(root.needs(l), root.row_room).length))

    Repeater {
        model: root.rows

        Rectangle {
            id: tab_well
            required property var modelData

            Layout.fillWidth: !root.pills
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: tab_row.implicitWidth + root.well_pad * 2
            implicitHeight: root.row_height
            radius: Style.radius(4) + root.well_pad
            color: root.st.tab_well

            // The inner shadow along the well's top edge.
            Rectangle {
                visible: root.well_pad > 0
                x: parent.radius
                y: 1
                width: parent.width - parent.radius * 2
                height: 1
                color: Qt.alpha(Theme.bg_shadow, 0.35)
            }

            RowLayout {
                id: tab_row
                readonly property var modelData: tab_well.modelData

                x: root.well_pad
                y: root.well_pad
                width: parent.width - root.well_pad * 2
                spacing: root.well_pad > 0 ? 2 : root.spacing

                Repeater {
                    model: tab_row.modelData

                    MenuTab {
                        id: tab
                        required property int modelData

                        Layout.fillWidth: !root.pills
                        Layout.preferredWidth: root.pills ? -1 : root.label_needs[tab.modelData] || 0
                        implicitHeight: root.tab_height
                        base_radius: root.pills && root.well_pad <= 0 ? 12 : 4
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
}
