// home/quickshell/.config/quickshell/bar/modules/CommandStatus.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"

BarModule {
    id: root
    module_name: "cmdstatus"
    has_popup: false
    // Each pill washes and titles its own tooltip; the module-wide wash would light every pill at once.
    wash: false

    readonly property var pills: CommandStatusState.entries.map(e => ({ id: e.id, result: CommandStatusState.results[e.id] })).filter(p => p.result && !p.result.hidden)
    property string hovered_id: ""
    readonly property var hovered_result: root.hovered_id !== "" ? CommandStatusState.result_of(root.hovered_id) : null

    shown: root.pills.length > 0
    tooltip_title: root.hovered_id
    tooltip_text: root.hovered_result ? root.hovered_result.tooltip : ""
    onTooltip_textChanged: if (root.hovered) Tooltip.show(root, root.tooltip_text, root.tooltip_title)
    onTooltip_titleChanged: if (root.hovered) Tooltip.show(root, root.tooltip_text, root.tooltip_title)
    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: row.implicitHeight

    Component.onCompleted: CommandStatusState.mounted_modules++
    Component.onDestruction: CommandStatusState.mounted_modules--

    function color_of(cls) {
        if (cls === "active") return Theme.theme_primary;
        if (cls === "warn") return Theme.warning;
        if (cls === "error") return Theme.error;
        return Style.bar_fg;
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            model: root.pills

            Item {
                id: pill
                required property var modelData
                implicitWidth: label.implicitWidth
                implicitHeight: label.implicitHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: Style.bar_radius(4)
                    color: Style.bar_hover_bg
                    opacity: pill_hover.hovered ? 0.5 : 0
                }

                Text {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.modelData.result.text
                    textFormat: Text.PlainText
                    color: root.color_of(pill.modelData.result.class)
                    font.family: Style.bar_font_family
                    style: Style.bar_text_style
                    styleColor: Style.bar_glow_color
                    font.pixelSize: Style.bar_font_size
                }

                HoverHandler {
                    id: pill_hover
                    onHoveredChanged: {
                        if (hovered) root.hovered_id = pill.modelData.id;
                        else if (root.hovered_id === pill.modelData.id) root.hovered_id = "";
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => CommandStatusState.click(pill.modelData.id, mouse.button === Qt.RightButton)
                }
            }
        }
    }
}
