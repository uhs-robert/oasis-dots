// home/quickshell/.config/quickshell/popups/keeptabs/MissionUsage.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/goldeneye" as Goldeneye
import "../../lock/skins/goldeneye" as Watch
import "../../services"
import "../../theme"
import "../../theme/Watch.js" as W

// GoldenEye's usage in the bar's own dress: per limit a caps label, the percent in seven-segment digits on the clock chip, a warm segment strip and when it resets. Inputs as in UsageView.
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

                delegate: ColumnLayout {
                    id: limit
                    required property var modelData

                    width: limit_list.width
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: limit.modelData.label.toUpperCase()
                        color: limit.modelData.percent > 100 ? Style.pal.error : Style.wk.soft
                        font.family: W.head_font
                        font.pixelSize: root.st.fs(-5)
                        font.letterSpacing: 1
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // The bar clock's dark chip; the palette panel stands in where the current style has none.
                        Rectangle {
                            Layout.preferredWidth: percent_text.implicitWidth + 14
                            Layout.preferredHeight: percent_text.implicitHeight + 6
                            radius: 2
                            color: Style.bar_clock_bg.a > 0 ? Style.bar_clock_bg : Style.wk.panel_top

                            Text {
                                id: percent_text
                                anchors.centerIn: parent
                                                text: String(Math.round(limit.modelData.percent))
                                color: limit.modelData.percent > 100 ? Style.pal.error : Style.wk.lit
                                font.family: W.digit_font
                                font.pixelSize: root.st.fs(3)
                            }
                        }

                        Text {
                            text: "%"
                            color: Style.wk.mid
                            font.family: W.mono_font
                            font.pixelSize: root.st.fs(-2)
                        }

                        Item { Layout.fillWidth: true }

                        Goldeneye.SegmentStrip {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.rightMargin: 4
                            count: 14
                            seg_width: 7
                            seg_height: 14
                            value: Math.min(1, limit.modelData.percent / 100)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: limit.modelData.resets !== ""
                        elide: Text.ElideRight
                        text: ("Resets " + limit.modelData.resets).toUpperCase()
                        color: Style.wk.soft
                        font.family: W.mono_font
                        font.pixelSize: root.st.fs(-3)
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
