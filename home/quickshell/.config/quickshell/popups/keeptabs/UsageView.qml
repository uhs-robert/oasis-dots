import QtQuick
import QtQuick.Layouts
import qs.components
import qs.theme
import qs.services
import "KeeptabsFormat.js" as Fmt

// The Usage tab: Claude usage bars from ClaudeUsageState, which it reads directly. The popup sets only `st`;
// a layout's Usage view (keeptabs/<prefix>Usage.qml) implements the same properties. `draws_footer` as in AgentsView.
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
            spacing: 6
            model: ClaudeUsageState.rows

            delegate: Rectangle {
                id: usage_row
                required property var modelData

                width: ListView.view.width
                height: 56
                radius: Style.radius(4)
                color: "transparent"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: usage_row.modelData.label
                            color: root.st.text_fg
                            font.bold: true
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-1)
                        }

                        Text {
                            text: usage_row.modelData.percent + "% used"
                            color: Fmt.context_bar_color(usage_row.modelData.percent, root.colors)
                            font.bold: true
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-2)
                        }
                    }

                    Meter {
                        Layout.fillWidth: true
                        visible: root.st.segmented_levels
                        segment_count: 40
                        implicitHeight: Style.px(8)
                        value: usage_row.modelData.percent / 100
                        on_color: Fmt.context_bar_color(usage_row.modelData.percent, root.colors)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        visible: !root.st.segmented_levels
                        radius: Style.radius(4)
                        color: Style.pal.bg_surface

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(100, usage_row.modelData.percent)) / 100
                            height: parent.height
                            radius: Style.radius(4)
                            color: Fmt.context_bar_color(usage_row.modelData.percent, root.colors)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        visible: usage_row.modelData.resets !== ""
                        text: "resets " + usage_row.modelData.resets
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }
        }
    }
}
