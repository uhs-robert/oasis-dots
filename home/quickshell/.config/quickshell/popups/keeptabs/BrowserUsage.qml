import QtQuick
import QtQuick.Layouts
import qs.styles.ps2.widgets
import qs.theme
import qs.services
import qs.features.clock
import "KeeptabsFormat.js" as Fmt

// The Usage tab as the PS2 Browser's card selection screen: each limit is a memory card whose free space
// (100 minus the percent used) is the glowing bar. Same contract as UsageView.qml.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : Theme.theme_primary_light
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-4)
            font.weight: Font.Light
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.5
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
            spacing: 10
            model: ClaudeUsageState.rows

            delegate: Item {
                id: card
                required property var modelData
                readonly property real used: Math.max(0, Math.min(100, card.modelData.percent))

                // Inset so the Block's shadow and glow are not cut by the list clip.
                x: 3
                width: ListView.view.width - 8
                height: card_col.implicitHeight + 16

                Block {
                    anchors.fill: parent
                    selected: true
                }

                ColumnLayout {
                    id: card_col
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 0

                    ConfigRow {
                        Layout.fillWidth: true
                        label: card.modelData.label
                        value: "Free space " + Math.round(100 - card.used) + "%"
                        level: (100 - card.used) / 100
                        level_color: card.used < 60 ? Theme.theme_primary_light : Fmt.context_bar_color(card.used, root.colors)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 3
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: card.modelData.resets !== "" ? "resets " + card.modelData.resets : ""
                            color: Theme.theme_primary_light
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.2
                        }

                        Text {
                            text: card.modelData.percent + "% used"
                            color: Theme.fg_strong
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                            font.letterSpacing: 1.2
                        }
                    }
                }
            }
        }
    }
}
