// home/quickshell/.config/quickshell/popups/keeptabs/PkmnUsage.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "../weather"

// The Usage tab as a Trainer Card: each limit is a name, an EXP-style bar and a percent, with its reset in a
// TIME line. Contract as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var shades: Style.pixel_shades
    readonly property bool mono: Style.device_model === "dmg"

    PixelBox {
        id: card
        anchors.fill: parent
        fill: root.shades[0]
        rings: [root.shades[2], root.shades[0], root.shades[3]]
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: card.edge + 6
        spacing: 6

        Text {
            text: "TRAINER CARD"
            color: root.shades[3]
            font.family: root.st.title_font_family
            font.pixelSize: 8
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 2
            color: root.shades[2]
        }

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading && !root.mono ? Style.pal.warning : root.shades[2]
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "No usage data yet"
            color: root.shades[2]
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ClaudeUsageState.rows.length > 0
            clip: true
            spacing: 8
            model: ClaudeUsageState.rows

            delegate: ColumnLayout {
                id: limit
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
                        text: limit.modelData.label.toUpperCase()
                        color: root.shades[3]
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    Text {
                        text: "EXP " + limit.modelData.percent + "%"
                        color: limit.modelData.percent >= 85 && !root.mono ? Style.pal.error : root.shades[3]
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }

                DexStatBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    value: limit.modelData.percent / 100
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    visible: limit.modelData.resets !== ""
                    text: "TIME " + limit.modelData.resets
                    color: root.shades[2]
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                }
            }
        }
    }
}
