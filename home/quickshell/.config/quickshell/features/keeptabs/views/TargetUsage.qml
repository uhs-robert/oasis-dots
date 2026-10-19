pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.features.keeptabs
import qs.features.clock

// The Usage tab as the cockpit's power allocation: one vertical targeting scale per limit, like the LSR, SHD and ENG columns.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property color vec: root.st.text_primary
    readonly property color hot: root.st.meter_hot.a > 0 ? root.st.meter_hot : Theme.theme_label
    readonly property var names: ["LSR", "SHD", "ENG", "PWR"]

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

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ClaudeUsageState.rows.length > 0
            spacing: 10

            Repeater {
                model: ClaudeUsageState.rows

                ColumnLayout {
                    id: column
                    required property var modelData
                    required property int index
                    readonly property real pct: Math.max(0, Math.min(100, column.modelData.percent))
                    readonly property color tone: column.pct >= 85 ? root.hot : root.vec

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    spacing: 4

                    Text {
                        text: root.names[column.index] || "PWR"
                        color: column.tone
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-2)
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: column.modelData.label
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }

                    Item {
                        id: scale
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property int pitch: 4
                        readonly property int tick_count: Math.max(2, Math.floor((scale.height - 1) / scale.pitch) + 1)
                        readonly property int lit_ticks: column.pct > 0 ? Math.round(column.pct / 100 * (scale.tick_count - 1)) : -1
                        readonly property real tip_y: scale.height - 1 - Math.max(0, scale.lit_ticks) * scale.pitch

                        Repeater {
                            model: scale.tick_count

                            Rectangle {
                                id: tick
                                required property int index
                                readonly property bool is_major: tick.index % 5 === 0
                                readonly property bool is_lit: tick.index <= scale.lit_ticks

                                x: 0
                                y: scale.height - 1 - tick.index * scale.pitch
                                width: tick.is_major ? 16 : 9
                                height: 1
                                color: Qt.alpha(column.tone, tick.is_lit ? 0.9 : 0.22)
                            }
                        }

                        Text {
                            x: 22
                            y: Math.max(0, Math.min(scale.height - height, scale.tip_y - height / 2))
                            text: column.modelData.percent + "%"
                            color: column.tone
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                            font.bold: true
                        }
                    }

                    Text {
                        text: "RECHG"
                        color: root.st.text_muted
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                        font.letterSpacing: 1.5
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: Math.ceil(recharge_metrics.height) * 2
                        verticalAlignment: Text.AlignTop
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: column.modelData.resets !== "" ? column.modelData.resets : "--"
                        color: root.st.text_fg
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-4)
                    }
                }
            }
        }
    }

    FontMetrics {
        id: recharge_metrics
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-4)
    }
}
