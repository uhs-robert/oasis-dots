import QtQuick
import QtQuick.Layouts
import qs.ui.effects
import qs.styles.ff7.widgets as Ff7
import qs.features.keeptabs
import qs.theme
import qs.ui.gauges
import qs.features.clock
import "KeeptabsFormat.js" as Fmt

// The Usage tab as the FF7 materia AP page: each limit is an orb with an AP bar that reads MASTERED at 100%,
// under a help window that carries the status line and every reset. The contract is in UsageView.qml.
Item {
    id: root

    property var st: Style
    property bool draws_footer: false

    readonly property var colors: ({ error: Style.pal.error, ok: Style.pal.ok, warning: Style.pal.warning, text_primary: root.st.text_primary, text_dim: root.st.text_dim })
    readonly property var orb_colors: [Style.materia_palette.days.green, Style.materia_palette.days.blue, Style.materia_palette.days.purple, Style.materia_palette.days.yellow, Style.materia_palette.days.red]
    readonly property int pad: 8

    Ff7.Ff7Window {
        id: help_window
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: help_col.implicitHeight + 2 * root.pad

        Column {
            id: help_col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.pad
            spacing: 2

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: ClaudeUsageState.loading ? "Loading…" : ClaudeUsageState.error ? ClaudeUsageState.error : (ClaudeUsageState.updated > 0 ? "Claude usage · updated " + TimeFormat.format(new Date(ClaudeUsageState.updated)) : "Claude usage")
                color: ClaudeUsageState.error && !ClaudeUsageState.loading ? Style.pal.warning : root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-2)
            }
        }
    }

    Ff7.Ff7Window {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: help_window.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom

        Text {
            anchors.centerIn: parent
            visible: ClaudeUsageState.rows.length === 0 && !ClaudeUsageState.loading
            text: ClaudeUsageState.error ? "" : "No usage data yet"
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-1)
        }

        ListView {
            anchors.fill: parent
            anchors.margins: root.pad
            visible: ClaudeUsageState.rows.length > 0
            clip: true
            spacing: 6
            model: ClaudeUsageState.rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: limit
                required property var modelData
                required property int index
                readonly property real pct: Math.max(0, Math.min(100, limit.modelData.percent))
                readonly property bool mastered: limit.pct >= 100
                readonly property var projection: ClaudeUsageState.projection_of(limit.modelData)

                width: ListView.view.width
                height: Math.max(Style.px(40), limit_col.implicitHeight + 6)

                MateriaOrb {
                    id: orb
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.px(22)
                    height: Style.px(22)
                    color: root.orb_colors[limit.index % root.orb_colors.length]
                    glow: limit.mastered
                }

                ColumnLayout {
                    id: limit_col
                    anchors.left: orb.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: limit.modelData.label
                            color: root.st.text_fg
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }

                        Text {
                            text: limit.mastered ? "MASTERED" : limit.modelData.percent + "%"
                            color: limit.mastered ? Style.pal.warning : Fmt.context_bar_color(limit.pct, root.colors)
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                            font.bold: true
                        }
                    }

                    AtbBar {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        ticks: true
                        value: limit.pct / 100
                        fill_color: limit.mastered ? Style.pal.warning : Fmt.context_bar_color(limit.pct, root.colors)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: limit.modelData.resets !== ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: "resets " + limit.modelData.resets
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: limit.projection.shown
                        elide: Text.ElideRight
                        text: limit.projection.text
                        color: limit.projection.over ? Style.pal.warning : root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }
        }
    }
}
