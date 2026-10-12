// home/quickshell/.config/quickshell/popups/keeptabs/MissionUsage.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/goldeneye" as Goldeneye
import "../../lock/skins/goldeneye" as Watch
import "../../services"
import "../../theme"
import "../../theme/Watch.js" as W

// GoldenEye's usage as the watch's gauges: a dial per limit with when it resets. Inputs as in UsageView.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    // Goldeneye's own popup frame already draws the green panel; a borrowed layout draws it here.
    Watch.PanelShape {
        anchors.fill: parent
        visible: !root.st.frame_watch
        cut: 12
        notches: false
        top_color: Style.wk.panel_top
        bottom_color: Style.wk.panel_bottom
        edge: Style.wk.edge
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: (ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")).toUpperCase()
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.error : Style.wk.soft
            font.family: W.head_font
            font.pixelSize: root.st.fs(-5)
            font.letterSpacing: 1
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 24
            visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "NO USAGE DATA YET"
            color: Style.wk.dim
            font.family: W.mono_font
            font.pixelSize: root.st.fs(-2)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: limit_list
                anchors.fill: parent
                visible: ClaudeUsageState.rows.length > 0
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: ClaudeUsageState.rows

                delegate: Item {
                    id: limit
                    required property var modelData

                    width: limit_list.width
                    height: Style.px(76)

                    Goldeneye.GaugeDial {
                        id: dial
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        size: Style.px(70)
                        value: limit.modelData.percent / 100
                    }

                    ColumnLayout {
                        anchors.left: dial.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: limit.modelData.label.toUpperCase()
                            color: Style.wk.lit
                            font.family: W.mono_font
                            font.pixelSize: root.st.fs(-1)
                        }

                        Goldeneye.ReadoutLine {
                            Layout.fillWidth: true
                            label: "USED"
                            digits: String(Math.round(limit.modelData.percent))
                            unit: "%"
                            alert: limit.modelData.percent > 100
                        }

                        Goldeneye.ReadoutLine {
                            Layout.fillWidth: true
                            visible: limit.modelData.resets !== ""
                            label: "RESETS"
                            text: limit.modelData.resets.toUpperCase()
                        }
                    }
                }
            }

            Goldeneye.ScanStatic {
                anchors.fill: parent
                scanning: ClaudeUsageState.loading
            }
        }
    }
}
