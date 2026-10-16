import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "../weather"
import "KeeptabsFormat.js" as Fmt

// CRT: the WeatherStar 4000 "Almanac" page, one column per usage limit where the sun and moon times sat.
// Reads ClaudeUsageState directly; contract as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: Theme.fg_strong, text_dim: root.st.text_dim })
    readonly property int row_count: ClaudeUsageState.rows.length

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Text {
            text: "Almanac"
            color: Theme.theme_secondary
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
            style: Text.Outline
            styleColor: Theme.bg_shadow
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0

            WsPanel {
                anchors.fill: parent
            }

            Text {
                anchors.centerIn: parent
                visible: root.row_count === 0 && !ClaudeUsageState.loading
                text: ClaudeUsageState.error ? "" : "No usage data yet"
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }

            GridLayout {
                anchors.fill: parent
                anchors.margins: 8
                visible: root.row_count > 0
                columns: Math.max(1, Math.min(root.row_count, 3))
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ClaudeUsageState.rows

                    ColumnLayout {
                        id: cell
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignTop
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: cell.modelData.label.replace(/^Current /, "")
                            color: Theme.theme_secondary
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                            style: Text.Outline
                            styleColor: Theme.bg_shadow
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.percent + "%"
                            color: Fmt.context_bar_color(cell.modelData.percent, root.colors)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.font_size * 2
                            style: Text.Outline
                            styleColor: Theme.bg_shadow
                        }

                        SegBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 9
                            count: 10
                            last_lit: Math.round(Math.max(0, Math.min(100, cell.modelData.percent)) / 10) - 1
                            on_color: Fmt.context_bar_color(cell.modelData.percent, root.colors)
                            off_color: Qt.alpha(Theme.bg_shadow, 0.55)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            visible: cell.modelData.resets !== ""
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: "Resets " + cell.modelData.resets
                            color: Theme.fg_strong
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                            style: Text.Outline
                            styleColor: Theme.bg_shadow
                        }
                    }
                }
            }

            Scanlines {
                anchors.fill: parent
                visible: root.st.scanlines
                color: root.st.scanline_color
                period: root.st.scanline_period
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_muted
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }
}
