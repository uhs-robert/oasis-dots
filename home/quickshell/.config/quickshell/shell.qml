//@ pragma UseQApplication
//@ pragma Env mesa_glthread=false
import QtQuick
import Quickshell
import qs.features.bar
import qs.features.bar_editor
import qs.theme.transitions
import qs.features.lock
import qs.features.overview
import qs.services
import qs.theme
import qs.features.settings
import qs.features.power
import qs.features.clock
import qs.features.weather
import qs.features.launcher
import qs.features.screenshot
import qs.features.screen_select
import qs.features.display
import qs.features.osd
import qs.features.notifications
import qs.features.start
import qs.features.tray
import qs.features.system
import qs.features.bluetooth
import qs.features.network
import qs.features.media
import qs.features.keeptabs
import qs.features.updates
import qs.features.voice
import qs.features.popups
import qs.features.audio
import qs.features.style
import qs.features.submap_hints
import "features/bar/BarLayout.js" as BarLayout

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

                readonly property var rule: BarSettings.rule_for(screen_scope.modelData)
                readonly property bool has_bar: screen_scope.rule !== null && screen_scope.rule.bar !== false
                readonly property string bar_position: screen_scope.has_bar ? BarSettings.position_for(screen_scope.rule) : "top"
                readonly property bool bar_bottom: screen_scope.bar_position === "bottom"
                readonly property bool bar_vertical: BarLayout.is_vertical(screen_scope.bar_position)
                readonly property int bar_height: BarSettings.height_for(screen_scope.rule)
                readonly property var frame: ScreenFrames.layout_for(screen_scope.modelData)
                // The last frame, held so the frame's bindings never see null while its loader drops it.
                property var drawn_frame: null
                onFrameChanged: if (screen_scope.frame) screen_scope.drawn_frame = screen_scope.frame
                Component.onCompleted: screen_scope.drawn_frame = screen_scope.frame

                LazyLoader {
                    id: bar_loader
                    active: screen_scope.has_bar

                    PanelWindow {
                        readonly property Item bar_item: bar

                        screen: screen_scope.modelData
                        color: "transparent"
                        // The floating strip's set-in from the screen edge is part of the window, so it is reserved too.
                        // A side bar is that thick as a column; its length is the screen's (top and bottom both anchored).
                        readonly property real thickness: screen_scope.bar_height + (Style.strip_floats ? Style.bar_strip_inset : 0)
                        implicitHeight: screen_scope.bar_vertical ? 0 : thickness
                        implicitWidth: screen_scope.bar_vertical ? thickness : 0
                        // Under a frame its zone windows reserve the bar's edge too, so the bar ignores them all
                        // instead of shrinking between the side zones.
                        exclusiveZone: screen_scope.frame ? -1 : thickness

                        // Each position anchors the three edges it spans: the screen edge and both neighbours.
                        anchors {
                            top: screen_scope.bar_position !== "bottom"
                            bottom: screen_scope.bar_position !== "top"
                            left: screen_scope.bar_position !== "right"
                            right: screen_scope.bar_position !== "left"
                        }

                        Bar {
                            id: bar
                            anchors.fill: parent
                            screen_name: screen_scope.modelData.name
                            rule: screen_scope.rule
                            frame: screen_scope.frame
                        }

                        StyleTransition {
                            anchors.fill: parent
                            target: bar
                            shown: true
                        }
                    }
                }

                LazyLoader {
                    active: screen_scope.frame !== null && screen_scope.drawn_frame !== null

                    ScreenFrame {
                        screen: screen_scope.modelData
                        layout: screen_scope.drawn_frame
                    }
                }

                PopupScrim {
                    screen: screen_scope.modelData
                    frame: screen_scope.frame
                }

                HotCorner {
                    screen: screen_scope.modelData
                    overview: overview_window
                    bottom: screen_scope.bar_bottom
                }

                SubmapTab {
                    screen: screen_scope.modelData
                    screen_name: screen_scope.modelData.name
                    line_width: bar_loader.item && bar_loader.item.bar_item.has_center ? bar_loader.item.bar_item.center_span : 260
                    line_shift: bar_loader.item && bar_loader.item.bar_item.has_center ? bar_loader.item.bar_item.center_tail / 2 : 0
                    bar_present: screen_scope.has_bar
                    bottom: screen_scope.bar_bottom
                    side: screen_scope.bar_vertical ? screen_scope.bar_position : ""
                    chip_shown: !!bar_loader.item && (bar_loader.item.bar_item.has_mode_chip || bar_loader.item.bar_item.has_frame_chip)
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

    Variants {
        model: ClickHints.active ? Quickshell.screens : []

        delegate: Component {
            ClickHintsOverlay {}
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
        name: "confirm"
        ConfirmPopup {}
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
    HyprvimPrompt {
        id: hyprvim_prompt
    }
    HyprvimPromptIpc {
        prompt: hyprvim_prompt
    }
    AgentsProvider {}
    AppsProvider {}
    ClipboardProvider {}
    EmojiProvider {}
    DirsProvider {}
    KeybindsProvider {}
    ChoicesProvider {}
    PickerVoice {
        id: picker_voice
    }
    PopupIpc {}
    PickerIpc {
        voice: picker_voice
    }
    BrightnessIpc {}
    NotificationsIpc {}
    StyleIpc {}
    TransitionsIpc {}
    WeatherIpc {}
    SettingsIpc {}
    GreeterSync {}
    ScreenShare {}
    ScreenFrameSync {}
    FrameExport {}
    PowerIpc {}
    ConfirmIpc {}
    ScreenshotIpc {}
    ZoomIpc {}
    ClickHintsIpc {}
    SoundIpc {}
    CommandStatusIpc {}
    CalendarIpc {}
    LockPreview {
        id: lock_preview
    }
    LockIpc {
        previewer: lock_preview
    }
    TooltipShelf {}
    NotificationToasts {}
    Osd {
        id: osd
    }
    OsdIpc {
        osd: osd
    }
    WhichKey {
        id: whichkey
    }
    Binding {
        target: SubmapState
        property: "whichkey_open"
        value: whichkey.visible
    }
    WhichKeyIpc {
        whichkey: whichkey
    }
    Variants {
        model: Quickshell.screens
        WindowTargetOverlay {}
    }
    Variants {
        model: Quickshell.screens
        SubmapHintBar {}
    }
    SubmapHintIpc {}
    Variants {
        model: BarEditor.active ? Quickshell.screens : []
        BarEditorWindow {}
    }
    BarEditorIpc {}
    Overview {
        id: overview_window
    }
    OverviewIpc {
        overview: overview_window
    }
    TmuxOverview {
        id: tmux_overview_window
    }
    TmuxOverviewIpc {
        tmux_overview: tmux_overview_window
    }
}
