import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.keeptabs
import qs.features.clock

// The Usage tab as `:checkhealth claude`: a "claude: usage" section, one OK/WARNING/ERROR line per limit and an
// ADVICE line for when it resets. The levels follow ClaudeUsageState's own warning thresholds (80% for the
// session, 90% for weekly limits), plus an error from 95%. Contract as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var level_colors: ({ OK: Style.pal.ok, WARNING: Style.pal.warning, ERROR: Style.pal.error, ADVICE: Style.pal.info, "": root.st.text_dim })

    function level_of(row) {
        if (row.percent >= 95) return "ERROR";
        return row.percent >= (/session/i.test(row.label) ? 80 : 90) ? "WARNING" : "OK";
    }

    readonly property var report_lines: {
        const lines = [];
        if (ClaudeUsageState.loading) {
            lines.push({ level: "WARNING", text: "fetching usage…", indent: false });
        } else if (ClaudeUsageState.error) {
            lines.push({ level: "ERROR", text: ClaudeUsageState.error, indent: false });
        } else if (ClaudeUsageState.rows.length === 0) {
            lines.push({ level: "WARNING", text: "no usage data yet", indent: false });
        }
        for (const row of ClaudeUsageState.rows) {
            lines.push({ level: root.level_of(row), text: row.percent + "% used · " + row.label, indent: false });
            if (row.resets !== "") lines.push({ level: "ADVICE", text: "resets " + row.resets, indent: true });
            const projection = ClaudeUsageState.projection_of(row);
            // Under pace is a plain info line, which checkhealth draws without a level badge.
            if (projection.shown) lines.push({ level: projection.over ? "WARNING" : "", text: projection.over ? "on pace to hit the limit by " + projection.when : "on pace for ~" + projection.end_percent + "% by " + projection.when, indent: true });
        }
        return lines;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Rectangle {
            Layout.alignment: Qt.AlignLeft
            implicitWidth: section_text.implicitWidth + 12
            implicitHeight: section_text.implicitHeight + 2
            radius: 2
            color: Qt.alpha(Style.pal.info, 0.18)

            Text {
                id: section_text
                anchors.centerIn: parent
                text: "claude: usage"
                color: Style.pal.info
                font.family: root.st.mono_font
                font.pixelSize: root.st.fs(-2)
                font.bold: true
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            visible: ClaudeUsageState.updated > 0
            text: "updated " + (ClaudeUsageState.updated > 0 ? TimeFormat.format(new Date(ClaudeUsageState.updated)) : "")
            color: root.st.text_dim
            font.family: root.st.mono_font
            font.pixelSize: root.st.fs(-3)
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: root.report_lines
            boundsBehavior: Flickable.StopAtBounds

            delegate: RowLayout {
                id: report_line
                required property var modelData

                width: ListView.view.width
                spacing: 6

                Item {
                    Layout.preferredWidth: report_line.modelData.indent ? 14 : 0
                }

                Text {
                    text: "-"
                    color: root.st.text_dim
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-2)
                }

                Rectangle {
                    visible: report_line.modelData.level !== ""
                    implicitWidth: level_text.implicitWidth + 8
                    implicitHeight: level_text.implicitHeight
                    radius: 2
                    color: Qt.alpha(root.level_colors[report_line.modelData.level], 0.18)

                    Text {
                        id: level_text
                        anchors.centerIn: parent
                        text: report_line.modelData.level + (report_line.modelData.level === "ADVICE" ? ":" : "")
                        color: root.level_colors[report_line.modelData.level]
                        font.family: root.st.mono_font
                        font.pixelSize: root.st.fs(-3)
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: report_line.modelData.text
                    color: report_line.modelData.level === "" ? root.st.text_dim : report_line.modelData.level === "ADVICE" ? root.st.text_muted : root.st.text_fg
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-2)
                }
            }
        }
    }
}
