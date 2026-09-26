//@ pragma UseQApplication
// home/quickshell/.config/quickshell/shell.qml
import QtQuick
import Quickshell
import "./bar"
import "./components"
import "./components/transitions"
import "./picker"
import "./popups"
import "./services"

ShellRoot {
    id: root

    BundledFonts {}

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Scope {
                id: screen_scope
                required property var modelData

                readonly property var rule: BarConfig.rule_for(screen_scope.modelData)
                readonly property bool has_bar: screen_scope.rule !== null && screen_scope.rule.bar !== false

                PanelWindow {
                    visible: screen_scope.has_bar
                    screen: screen_scope.modelData
                    color: "transparent"
                    implicitHeight: BarConfig.height_for(screen_scope.rule)
                    exclusiveZone: screen_scope.has_bar ? implicitHeight : 0

                    anchors {
                        top: true
                        left: true
                        right: true
                    }

                    Bar {
                        id: bar
                        anchors.fill: parent
                        screen_name: screen_scope.modelData.name
                        rule: screen_scope.rule
                    }

                    StyleTransition {
                        anchors.fill: parent
                        target: bar
                        shown: screen_scope.has_bar
                    }
                }

                PopupScrim {
                    screen: screen_scope.modelData
                }

                SubmapTab {
                    screen: screen_scope.modelData
                    line_width: bar.center_width
                    bar_present: screen_scope.has_bar
                    chip_shown: bar.has_mode_chip
                }
            }
        }
    }

    Variants {
        model: Screenshot.selecting ? Quickshell.screens : []

        delegate: Component {
            RegionSelector {}
        }
    }

    ClockPopup {}
    StartPopup {}
    StylePopup {}
    VolumePopup {}
    BatteryPopup {}
    BluetoothPopup {}
    SystemPopup {}
    TrayPopup {}
    NetworkPopup {}
    KeeptabsPopup {}
    WeatherPopup {}
    UpdatesPopup {}
    MediaPopup {}
    ScreenshotPopup {}
    NotificationsPopup {}
    Picker {}
    HyprvimPrompt {}
    AppsProvider {}
    ClipboardProvider {}
    WindowsProvider {}
    PopupIpc {}
    PickerIpc {}
    BrightnessIpc {}
    NotificationsIpc {}
    StyleIpc {}
    PowerIpc {}
    ScreenshotIpc {}
    TooltipShelf {}
    NotificationToasts {}
    Osd {}
    WhichKey {}
}
