import QtQuick
import qs.theme
import qs.features.keeptabs
import qs.features.clock
import "../../../styles/terminal/widgets/WttrArt.js" as WttrArt
import "KeeptabsFormat.js" as Fmt

// The Usage tab as Claude Code's /usage screen: each limit a bold label, a text bar with its percentage, and a dim reset line.
// Contract as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    readonly property int text_px: root.st.fs(-2)
    // Reading metrics.font makes the advance rebind once the family and size land.
    readonly property real glyph_w: metrics.font.pixelSize > 0 ? Math.max(1, metrics.advanceWidth("M")) : 1
    readonly property real lh: Math.max(1, Math.floor(metrics.height))
    readonly property int cols: Math.floor(root.width / root.glyph_w)
    // The bar leaves room for "  100% used".
    readonly property int bar_cols: Math.max(8, root.cols - 12)
    readonly property var eighths: [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

    // Whole blocks, then one partial block, as /usage draws it; the track behind is a rectangle.
    function bar_text(percent) {
        const total = Math.round(Math.max(0, Math.min(100, percent)) / 100 * root.bar_cols * 8);
        const full = Math.floor(total / 8);
        return "█".repeat(full) + (full < root.bar_cols ? root.eighths[total % 8] : "");
    }

    FontMetrics {
        id: metrics
        font.family: root.st.mono_font
        font.pixelSize: root.text_px
    }

    Text {
        id: status
        width: parent.width
        elide: Text.ElideRight
        text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
        color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_muted
        font.family: root.st.mono_font
        font.pixelSize: root.text_px
        font.bold: true
    }

    Text {
        anchors.centerIn: parent
        visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading && !ClaudeUsageState.error
        text: "No usage data yet"
        color: root.st.text_dim
        font.family: root.st.mono_font
        font.pixelSize: root.text_px
    }

    ListView {
        y: status.height + root.lh / 2
        width: parent.width
        height: Math.max(0, root.height - y)
        visible: ClaudeUsageState.rows.length > 0
        clip: true
        spacing: root.lh
        model: ClaudeUsageState.rows

        delegate: Item {
            id: usage_row
            required property var modelData
            readonly property color level_color: Fmt.context_bar_color(usage_row.modelData.percent, root.colors)
            readonly property var projection: ClaudeUsageState.projection_of(usage_row.modelData)
            readonly property int reset_lines: usage_row.modelData.resets !== "" ? 1 : 0

            width: ListView.view.width
            height: (2 + usage_row.reset_lines + (usage_row.projection.shown ? 1 : 0)) * root.lh

            Text {
                width: parent.width
                height: root.lh
                elide: Text.ElideRight
                text: usage_row.modelData.label
                color: root.st.text_fg
                font.bold: true
                font.family: root.st.mono_font
                font.pixelSize: root.text_px
            }

            Rectangle {
                y: root.lh
                width: root.bar_cols * root.glyph_w
                height: root.lh
                color: Style.pal.bg_surface
            }

            Text {
                y: root.lh
                height: root.lh
                textFormat: Text.StyledText
                text: WttrArt.runs([[root.bar_text(usage_row.modelData.percent), String(usage_row.level_color)], [" ".repeat(Math.max(0, root.bar_cols - root.bar_text(usage_row.modelData.percent).length)) + "  " + usage_row.modelData.percent + "% used", String(root.st.text_fg)]])
                color: root.st.text_fg
                font.family: root.st.mono_font
                font.pixelSize: root.text_px
            }

            Text {
                y: 2 * root.lh
                width: parent.width
                height: root.lh
                elide: Text.ElideRight
                visible: usage_row.modelData.resets !== ""
                text: "Resets " + usage_row.modelData.resets
                color: root.st.text_dim
                font.family: root.st.mono_font
                font.pixelSize: root.text_px
            }

            Text {
                y: (2 + usage_row.reset_lines) * root.lh
                width: parent.width
                height: root.lh
                elide: Text.ElideRight
                visible: usage_row.projection.shown
                text: usage_row.projection.text.length <= root.cols ? usage_row.projection.text : "Projected: " + usage_row.projection.short
                color: usage_row.projection.over ? Style.pal.warning : root.st.text_dim
                font.family: root.st.mono_font
                font.pixelSize: root.text_px
            }
        }
    }
}
