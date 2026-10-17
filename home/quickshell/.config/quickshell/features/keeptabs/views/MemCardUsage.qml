import QtQuick
import QtQuick.Layouts
import qs.styles.ps1.widgets as Ps1
import qs.theme
import qs.features.keeptabs
import qs.features.clock
import "KeeptabsFormat.js" as Fmt

// The Usage tab as the BIOS memory card slots: each limit is a card whose used blocks are the percent. Contract as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property int card_blocks: 15
    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })

    // Any use at all shows at least one block.
    function blocks_used(pct) {
        return pct > 0 ? Math.max(1, Math.min(root.card_blocks, Math.round(pct * root.card_blocks / 100))) : 0;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Checking memory card..." : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : Theme.theme_primary_light
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-2)
            font.bold: true
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
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: ClaudeUsageState.rows

            delegate: Rectangle {
                id: slot
                required property var modelData
                required property int index
                readonly property int used_blocks: root.blocks_used(slot.modelData.percent)
                readonly property color fill: Fmt.context_bar_color(slot.modelData.percent, root.colors)

                width: ListView.view.width
                height: slot_col.implicitHeight + 16
                radius: 6
                color: Qt.alpha(Theme.bg_shadow, 0.35)
                border.width: 2
                border.color: Style.frame_border_color

                ColumnLayout {
                    id: slot_col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "MEMORY CARD " + (slot.index + 1)
                            color: Theme.theme_primary_light
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: slot.modelData.label
                            color: Style.text_strong
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                            style: Text.Raised
                            styleColor: Style.text_shadow
                        }

                        Text {
                            text: slot.modelData.percent + "%"
                            color: slot.fill
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                            font.bold: true
                        }
                    }

                    Item {
                        id: used_row
                        Layout.fillWidth: true
                        implicitHeight: Style.px(14)
                        readonly property real block_w: Math.max(2, (used_row.width - 2 * (root.card_blocks - 1)) / root.card_blocks)

                        Repeater {
                            model: root.card_blocks

                            Rectangle {
                                required property int index
                                readonly property bool used: index < slot.used_blocks

                                x: index * (used_row.block_w + 2)
                                width: used_row.block_w
                                height: used_row.height
                                radius: 2
                                color: used ? Qt.alpha(slot.fill, index === slot.used_blocks - 1 ? 1 : 0.6) : Qt.alpha(Theme.bg_shadow, 0.45)
                                border.width: 1
                                border.color: used ? Qt.lighter(slot.fill, 1.3) : Qt.alpha(Style.frame_border_color, 0.6)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            id: free_text
                            Layout.minimumWidth: implicitWidth
                            text: "FREE " + (root.card_blocks - slot.used_blocks) + " BLOCKS"
                            color: root.st.text_muted
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-5)
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        // The reset time as a small date panel.
                        Ps1.BiosPanel {
                            visible: slot.modelData.resets !== ""
                            Layout.maximumWidth: parent.width - free_text.implicitWidth - 16
                            Layout.preferredWidth: reset_text.implicitWidth + 12
                            Layout.preferredHeight: reset_text.implicitHeight + 6

                            Text {
                                id: reset_text
                                anchors.fill: parent
                                anchors.margins: 3
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                text: "RESETS " + slot.modelData.resets
                                color: Style.text_fg
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-5)
                            }
                        }
                    }
                }
            }
        }
    }
}
