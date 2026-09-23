//@ pragma UseQApplication
// home/quickshell/.config/quickshell/shell.qml
import QtQuick
import Quickshell
import "./bar"
import "./components"
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
            Scope {
                id: screen_scope
                required property var modelData

                PanelWindow {
                    screen: screen_scope.modelData
                    color: "transparent"
                    implicitHeight: 30
                    exclusiveZone: implicitHeight

                    anchors {
                        top: true
                        left: true
                        right: true
                    }

                    Bar {
                        id: bar
                        anchors.fill: parent
                        screen_name: screen_scope.modelData.name
                    }
                }

                SubmapTab {
                    screen: screen_scope.modelData
                    line_width: bar.center_width
                }
            }
        }
    }

    ClockPopup {}
    StartPopup {}
    VolumePopup {}
    BatteryPopup {}
    BluetoothPopup {}
    PopupIpc {}
    BrightnessIpc {}
    BarTooltip {}
}
