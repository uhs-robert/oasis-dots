import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services
import qs.popups.weather as Weather
import qs.features.clock
import "KeeptabsFormat.js" as Fmt

// The Usage tab as a Dragon Quest STATUS window: each limit is a row with an HP-style gauge, and its reset is the inn.
// Contract as UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    Weather.DqWindow {
        anchors.fill: parent
        anchors.topMargin: 6
        title: "STATUS"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
                color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 24
                visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
                text: ClaudeUsageState.error ? "" : "No usage data yet"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-1)
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: ClaudeUsageState.rows.length > 0
                clip: true
                spacing: 8
                model: ClaudeUsageState.rows

                delegate: ColumnLayout {
                    id: usage_row
                    required property var modelData

                    width: ListView.view.width
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: usage_row.modelData.label
                            color: root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                        }

                        Text {
                            text: usage_row.modelData.percent + "%"
                            color: Fmt.context_bar_color(usage_row.modelData.percent, root.colors)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                            font.bold: true
                        }
                    }

                    Weather.BattleGauge {
                        Layout.fillWidth: true
                        value: usage_row.modelData.percent / 100
                        fill_color: Fmt.context_bar_color(usage_row.modelData.percent, root.colors)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: usage_row.modelData.resets !== ""
                        text: "The inn restores you at " + usage_row.modelData.resets
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }
    }
}
