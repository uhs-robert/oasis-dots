import QtQuick
import QtQuick.Layouts
import "../../components/oasis" as Oasis
import "../../theme"
import "../../services"
import "KeeptabsFormat.js" as Fmt

// The Usage tab as horizons: each limit is a line with a sun at the percent used, "sunrise <resets>" at the far end.
// The contract is UsageView's.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property color sand: Theme.theme_secondary

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_muted
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
            spacing: 8
            model: ClaudeUsageState.rows

            delegate: Item {
                id: usage_row
                required property var modelData
                readonly property real level: Math.max(0, Math.min(100, usage_row.modelData.percent)) / 100
                readonly property color sun: usage_row.level >= 0.85 ? root.st.meter_hot : root.sand

                width: ListView.view.width
                height: Style.px(58)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: usage_row.modelData.label
                            color: root.st.text_strong
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: usage_row.modelData.percent + "% used"
                            color: usage_row.sun
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                            font.bold: true
                        }
                    }

                    Item {
                        id: horizon
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        readonly property real sun_size: 14
                        readonly property real sun_x: horizon.sun_size / 2 + (horizon.width - horizon.sun_size) * usage_row.level

                        Rectangle {
                            y: Math.round(horizon.height / 2)
                            width: horizon.width
                            height: 1
                            color: Qt.alpha(root.st.text_dim, 0.35)
                        }

                        Rectangle {
                            y: Math.round(horizon.height / 2)
                            width: horizon.sun_x
                            height: 1
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.alpha(usage_row.sun, 0) }
                                GradientStop { position: 1; color: usage_row.sun }
                            }
                        }

                        Rectangle {
                            x: horizon.sun_x - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: horizon.sun_size
                            height: horizon.sun_size
                            radius: width / 2
                            color: Qt.alpha(usage_row.sun, 0.2)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: usage_row.sun
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        visible: usage_row.modelData.resets !== ""
                        text: "sunrise " + usage_row.modelData.resets
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }

            footer: Item {
                width: ListView.view.width
                height: 20

                Oasis.MoonRule {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    color: Style.frame_border_color
                }
            }
        }
    }
}
