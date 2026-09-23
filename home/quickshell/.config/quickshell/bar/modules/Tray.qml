// home/quickshell/.config/quickshell/bar/modules/Tray.qml
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../services"

Row {
    id: root

    spacing: 10
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items.values

        Item {
            id: icon_root
            required property var modelData

            width: 16
            height: 16

            IconImage {
                anchors.fill: parent
                implicitSize: 16
                source: icon_root.modelData.icon
            }

            QsMenuAnchor {
                id: menu_anchor
                anchor.item: icon_root
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
                menu: icon_root.modelData.menu
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        if (menu_anchor.visible) menu_anchor.close(); else menu_anchor.open();
                    } else if (mouse.button === Qt.MiddleButton) {
                        icon_root.modelData.secondaryActivate();
                    } else if (icon_root.modelData.onlyMenu) {
                        if (menu_anchor.visible) menu_anchor.close(); else menu_anchor.open();
                    } else {
                        icon_root.modelData.activate();
                    }
                }
                onWheel: wheel => icon_root.modelData.scroll(wheel.angleDelta.y, false)
            }

            HoverHandler {
                onHoveredChanged: {
                    const label = icon_root.modelData.tooltipTitle || icon_root.modelData.title;
                    if (hovered && label) Tooltip.show(icon_root, label);
                    else Tooltip.hide();
                }
            }
        }
    }
}
