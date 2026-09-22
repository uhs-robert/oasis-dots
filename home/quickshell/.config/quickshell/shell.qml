// home/quickshell/.config/quickshell/shell.qml
import QtQuick
import Quickshell
import "./bar"
import "./popups"
import "./services"

ShellRoot {
    id: root

    // First external (non-eDP) screen if one is connected, else the eDP screen.
    function pick_screens(screens) {
        const external = screens.filter(s => s.name.indexOf("eDP") !== 0);
        if (external.length > 0) return [external[0]];
        return screens.filter(s => s.name.indexOf("eDP") === 0);
    }

    Variants {
        model: root.pick_screens(Quickshell.screens)

        delegate: Component {
            PanelWindow {
                required property var modelData

                screen: modelData
                color: "transparent"
                implicitHeight: 30
                exclusiveZone: implicitHeight

                anchors {
                    top: true
                    left: true
                    right: true
                }

                Bar {
                    anchors.fill: parent
                }
            }
        }
    }

    TestPopup {}
    PopupIpc {}
}
