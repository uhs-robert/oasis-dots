// demo/overlay/shell.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Click-through key caps and end card for the showcase video; run alone with `qs -p demo/overlay`.
ShellRoot {
    id: root

    readonly property string output_name: Quickshell.env("DEMO_OUTPUT") || "HDMI-A-1"
    readonly property string mono_family: mono_font.status === FontLoader.Ready ? mono_font.name : "monospace"
    readonly property string sans_family: sans_font.status === FontLoader.Ready ? sans_font.name : "sans-serif"

    property var parts: []
    property string mode: "keys"
    property bool keys_on: false
    property bool card_on: false
    property bool window_on: false

    FontLoader {
        id: mono_font
        source: Qt.resolvedUrl("fonts/GeistMono-Variable.ttf")
    }

    FontLoader {
        id: sans_font
        source: Qt.resolvedUrl("fonts/Geist-Variable.ttf")
    }

    // A fresh surface maps above any layer that opened since the last one.
    function raise() {
        root.window_on = false;
        root.window_on = true;
    }

    function show_keys(items, kind) {
        root.mode = kind;
        root.parts = items;
        if (root.card_on) root.window_on = true;
        else root.raise();
        root.keys_on = true;
        off_timer.stop();
        fade_timer.restart();
    }

    function set_card(on) {
        root.card_on = on;
        if (on) {
            root.window_on = true;
            off_timer.stop();
        } else {
            off_timer.restart();
        }
    }

    function clear_all() {
        fade_timer.stop();
        root.keys_on = false;
        root.card_on = false;
        off_timer.restart();
    }

    Timer {
        id: fade_timer
        interval: 1200
        onTriggered: {
            root.keys_on = false;
            off_timer.restart();
        }
    }

    Timer {
        id: off_timer
        interval: 800
        onTriggered: if (!root.keys_on && !root.card_on) root.window_on = false
    }

    IpcHandler {
        target: "demo"

        function keys(label: string): void {
            root.show_keys(label.split(" + ").map(s => s.trim()).filter(s => s !== ""), "keys");
        }

        function mask(count: int): void {
            const dots = [];
            for (let i = 0; i < count; i++) dots.push("*");
            root.show_keys(dots, "mask");
        }

        function clear(): void {
            root.clear_all();
        }

        function card(show: bool): void {
            root.set_card(show);
        }
    }

    Loader {
        active: root.window_on
        sourceComponent: overlay_window
    }

    Component {
        id: overlay_window

        PanelWindow {
            id: win

            readonly property real k: Math.max(0.5, win.width / 2560)
            readonly property real kc: win.k * 1.4
            property bool ready: false

            screen: Quickshell.screens.find(s => s.name === root.output_name) || null
            visible: win.screen !== null
            color: "transparent"
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "demo-overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Component.onCompleted: win.ready = true

            Rectangle {
                anchors.fill: parent
                color: "#cc06080b"
                opacity: win.ready && root.card_on ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 28 * win.k
                opacity: win.ready && root.card_on ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: status === Image.Ready
                    source: Qt.resolvedUrl("logo.png")
                    width: 760 * win.k
                    height: width * implicitHeight / Math.max(1, implicitWidth)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 24 * win.k
                    text: "Dotfiles"
                    color: "#f4f7f9"
                    font.family: root.sans_family
                    font.pixelSize: 120 * win.k
                    font.weight: Font.Bold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Hyprland + HyprVim + QuickShell"
                    color: "#c3cdd4"
                    font.family: root.sans_family
                    font.pixelSize: 64 * win.k
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: 36 * win.k
                    text: "github.com/uhs-robert/oasis-dots"
                    color: "#8fa0ab"
                    font.family: root.mono_family
                    font.pixelSize: 44 * win.k
                }
            }

            Row {
                id: caps
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 150 * win.kc
                spacing: 20 * win.kc
                opacity: win.ready && root.keys_on && !root.card_on ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: root.keys_on ? 120 : 300 }
                }

                Repeater {
                    model: root.parts

                    delegate: Row {
                        id: unit

                        required property int index
                        required property string modelData

                        spacing: 20 * win.kc

                        Rectangle {
                            width: root.mode === "mask" ? 76 * win.kc : Math.max(96 * win.kc, cap_text.implicitWidth + 60 * win.kc)
                            height: 96 * win.kc
                            radius: 18 * win.kc
                            color: "#e6101418"
                            border.width: Math.max(1, 2 * win.kc)
                            border.color: "#59ffffff"

                            Text {
                                id: cap_text
                                anchors.centerIn: parent
                                visible: root.mode === "keys"
                                text: unit.modelData
                                color: "#f4f7f9"
                                font.family: root.mono_family
                                font.pixelSize: 46 * win.kc
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                visible: root.mode === "mask"
                                width: 24 * win.kc
                                height: width
                                radius: width / 2
                                color: "#f4f7f9"
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.mode === "keys" && unit.index < root.parts.length - 1
                            text: "+"
                            color: "#c3cdd4"
                            font.family: root.mono_family
                            font.pixelSize: 40 * win.kc
                        }
                    }
                }
            }
        }
    }
}
