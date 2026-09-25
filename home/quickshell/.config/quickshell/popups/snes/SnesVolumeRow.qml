// home/quickshell/.config/quickshell/popups/snes/SnesVolumeRow.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/snes" as Snes
import "../../theme"

// A Volume row the SNES way: devices as plain menu lines, level rows as party members (name, VOL gauge, value) in their own window.
Item {
    id: root

    property string label: ""
    property string key: ""
    property bool selected: false
    // Level rows (default sink/source, apps) carry a gauge; device rows are just names.
    property bool level_row: false
    property bool is_default: false
    property bool searchable: true
    property real volume: 0
    property bool muted: false
    signal clicked()
    signal moved(real value)
    signal mute_clicked()

    readonly property int pad: 10

    implicitHeight: root.level_row ? member.implicitHeight + 16 + menu_window.drop : Style.px(22)

    Snes.SnesWindow {
        id: menu_window
        visible: root.level_row
        anchors.fill: parent
        lit: root.selected
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }

    HandCursor {
        visible: root.selected
        x: root.level_row ? 6 : 2
        y: root.level_row ? 8 + Math.round((name_text.implicitHeight - height) / 2) : Math.round((root.height - height) / 2)
        width: 19
        height: 12
    }

    RowLayout {
        visible: !root.level_row
        anchors.fill: parent
        anchors.leftMargin: 26
        anchors.rightMargin: 4
        spacing: 6

        RowLabel {
            Layout.fillWidth: true
            elide: Text.ElideRight
            label: root.label
            color: root.is_default ? Theme.theme_secondary : Theme.fg_strong
            style: Text.Raised
            styleColor: Style.text_shadow
            font.family: Style.font_family
            font.pixelSize: Style.fs(-1)
        }

        KeyBadge {
            visible: Style.row_keys && root.key !== ""
            key: root.key
        }
    }

    ColumnLayout {
        id: member
        visible: root.level_row
        x: 26
        y: 8
        width: root.width - x - root.pad - menu_window.drop
        spacing: 3

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RowLabel {
                id: name_text
                Layout.fillWidth: true
                elide: Text.ElideRight
                label: root.label
                searchable: root.searchable
                color: Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-1)
            }

            Text {
                text: root.muted ? "" : ""
                color: root.muted ? Theme.theme_label : Theme.theme_primary_light
                font.family: Theme.font_family
                font.pixelSize: Style.fs(-2)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: root.mute_clicked()
                }
            }

            KeyBadge {
                visible: Style.row_keys && root.key !== ""
                key: root.key
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "VOL"
                color: Theme.theme_primary_light
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }

            Snes.SnesGauge {
                id: gauge
                Layout.fillWidth: true
                value: root.volume
                hot_from: 0.9
                dim: root.muted

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -4
                    anchors.bottomMargin: -4
                    onPressed: mouse => root.moved(Math.max(0, Math.min(1, mouse.x / Math.max(1, gauge.width))))
                    onPositionChanged: mouse => {
                        if (pressed) root.moved(Math.max(0, Math.min(1, mouse.x / Math.max(1, gauge.width))));
                    }
                }
            }

            Text {
                Layout.preferredWidth: value_metrics.advanceWidth("100")
                horizontalAlignment: Text.AlignRight
                text: Math.round(root.volume * 100)
                color: root.muted ? Style.text_muted : Theme.fg_strong
                style: Text.Raised
                styleColor: Style.text_shadow
                font.family: Style.font_family
                font.pixelSize: Style.fs(-3)
            }
        }
    }

    FontMetrics {
        id: value_metrics
        font.family: Style.font_family
        font.pixelSize: Style.fs(-3)
    }
}
