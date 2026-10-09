//@ pragma UseQApplication
//@ pragma Env mesa_glthread=false
// home/quickshell/.config/quickshell/shell.qml
import QtQuick
import Quickshell
import "./bar"
import "./components"
import "./components/transitions"
import "./lock"
import "./overview"
import "./tmux_overview"
import "./picker"
import "./popups"
import "./services"
import "./settings"

ShellRoot {
    id: root

    Component.onDestruction: {
        Screenshot.set_capture_opaque(false);
        Screenshot.send_share("");
    }

    BundledFonts {}

    Variants {
        model: Quickshell.screens

        delegate: Component {
            Scope {
                id: screen_scope
                required property var modelData

                readonly property var rule: BarConfig.rule_for(screen_scope.modelData)
                readonly property bool has_bar: screen_scope.rule !== null && screen_scope.rule.bar !== false

                LazyLoader {
                    id: bar_loader
                    active: screen_scope.has_bar

                    PanelWindow {
                        readonly property Item bar_item: bar

                        screen: screen_scope.modelData
                        color: "transparent"
                        implicitHeight: BarConfig.height_for(screen_scope.rule)
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
                            rule: screen_scope.rule
                        }

                        StyleTransition {
                            anchors.fill: parent
                            target: bar
                            shown: true
                        }
                    }
                }

                PopupScrim {
                    screen: screen_scope.modelData
                }

                HotCorner {
                    screen: screen_scope.modelData
                    overview: overview_window
                }

                SubmapTab {
                    screen: screen_scope.modelData
                    screen_name: screen_scope.modelData.name
                    line_width: bar_loader.item ? bar_loader.item.bar_item.center_width : 260
                    bar_present: screen_scope.has_bar
                    chip_shown: !!bar_loader.item && bar_loader.item.bar_item.has_mode_chip
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

    Variants {
        model: Zoom.active ? Quickshell.screens : []

        delegate: Component {
            ZoomLoupe {}
        }
    }

    Variants {
        model: Zoom.active ? Quickshell.screens : []

        delegate: Component {
            ZoomReticle {}
        }
    }

    LazyPopup {
        name: "clock"
        ClockPopup {}
    }
    LazyPopup {
        name: "start"
        StartPopup {}
    }
    LazyPopup {
        name: "power"
        PowerPopup {}
    }
    LazyPopup {
        name: "settings"
        SettingsPopup {
            previewer: lock_preview
        }
    }
    LazyPopup {
        name: "volume"
        VolumePopup {}
    }
    LazyPopup {
        name: "battery"
        BatteryPopup {}
    }
    LazyPopup {
        name: "bluetooth"
        BluetoothPopup {}
    }
    LazyPopup {
        name: "system"
        SystemPopup {}
    }
    LazyPopup {
        name: "tray"
        TrayPopup {}
    }
    LazyPopup {
        name: "network"
        NetworkPopup {}
    }
    LazyPopup {
        name: "keeptabs"
        KeeptabsPopup {}
    }
    LazyPopup {
        name: "weather"
        WeatherPopup {}
    }
    LazyPopup {
        name: "updates"
        UpdatesPopup {}
    }
    LazyPopup {
        name: "media"
        MediaPopup {}
    }
    LazyPopup {
        name: "screenshot"
        ScreenshotPopup {}
    }
    LazyPopup {
        name: "notifications"
        NotificationsPopup {}
    }
    LazyPopup {
        name: "picker"
        Picker {}
    }
    HyprvimPrompt {}
    AppsProvider {}
    ClipboardProvider {}
    EmojiProvider {}
    DirsProvider {}
    KeybindsProvider {}
    ChoicesProvider {}
    PopupIpc {}
    PickerIpc {}
    BrightnessIpc {}
    NotificationsIpc {}
    StyleIpc {}
    SettingsIpc {}
    GreeterSync {}
    ScreenShare {}
    PowerIpc {}
    ScreenshotIpc {}
    ZoomIpc {}
    LockPreview {
        id: lock_preview
    }
    LockIpc {
        previewer: lock_preview
    }
    TooltipShelf {}
    NotificationToasts {}
    Osd {}
    WhichKey {}
    Overview {
        id: overview_window
    }
    TmuxOverview {}
}
