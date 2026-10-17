pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.ui.frames
import qs.ui.gauges
import qs.theme
import qs.services
import qs.features.keeptabs
import qs.features.clock

// The Usage tab as the combat visor's ENERGY HUD: each limit reads as what is left of it, in energy tanks and a bar,
// red under 15. Reads ClaudeUsageState directly; the contract is UsageView's.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property color visor: Style.pal.primary
    readonly property color visor_light: Style.pal.primary_light
    readonly property bool animating: Popups.open_name === "keeptabs" && root.visible
    readonly property int low_energy: 15

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: ClaudeUsageState.loading ? "SCANNING…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "ENERGY HUD · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "ENERGY HUD")
            color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.visor
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
            font.letterSpacing: 2
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

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: limit_list
                anchors.fill: parent
                visible: ClaudeUsageState.rows.length > 0
                clip: true
                spacing: 6
                model: ClaudeUsageState.rows

                delegate: Item {
                    id: limit_row
                    required property var modelData
                    readonly property real energy: Math.max(0, Math.min(100, 100 - limit_row.modelData.percent))
                    readonly property color tone: limit_row.energy < root.low_energy ? Style.pal.red : root.visor_light

                    width: limit_list.width
                    height: Math.max(Style.px(66), limit_text.implicitHeight + 16)

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(root.visor, 0.04)
                    }

                    CornerBrackets {
                        anchors.fill: parent
                        color: Qt.alpha(limit_row.tone, 0.5)
                        inset: 0
                        arm: 5
                        all_corners: true
                    }

                    ColumnLayout {
                        id: limit_text
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: limit_row.modelData.label
                                color: root.st.text_fg
                                font.bold: true
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-2)
                            }

                            Text {
                                text: "ENERGY " + Math.round(limit_row.energy) + " · " + Math.round(limit_row.modelData.percent) + "% USED"
                                color: limit_row.tone
                                font.family: Style.number_font
                                font.pixelSize: root.st.fs(-2)
                            }
                        }

                        // One tank per tenth of the limit left.
                        SegBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 7
                            count: 10
                            gap: 3
                            last_lit: Math.round(limit_row.energy / 10) - 1
                            on_color: limit_row.tone
                            off_color: Qt.alpha(root.visor, 0.14)
                        }

                        SegBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            count: 40
                            gap: 1
                            last_lit: Math.round(limit_row.energy * 0.4) - 1
                            on_color: limit_row.tone
                            off_color: Qt.alpha(root.visor, 0.14)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            visible: limit_row.modelData.resets !== ""
                            text: "RECHARGE " + limit_row.modelData.resets
                            color: root.st.text_dim
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-4)
                        }
                    }
                }
            }

            // The scan-in: a lit band sweeping across the list while usage loads.
            Rectangle {
                id: sweep
                visible: ClaudeUsageState.loading
                width: 70
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.8; color: Qt.alpha(root.visor_light, 0.22) }
                    GradientStop { position: 1; color: Qt.alpha(root.visor_light, 0.6) }
                }

                NumberAnimation on x {
                    running: ClaudeUsageState.loading && root.animating
                    loops: Animation.Infinite
                    from: -sweep.width
                    to: sweep.parent.width
                    duration: 1100
                }
            }
        }
    }
}
