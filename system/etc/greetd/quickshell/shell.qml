// /etc/greetd/quickshell/shell.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme

// The login screen: the lock skin in the user's lock style, fullscreen under greetd, in a window as a preview otherwise.
ShellRoot {
    id: root

    Fonts {
        id: bundled_fonts
    }

    GreeterAudio {}

    // Opt-in: a preview normally opens one window, which skips the per-screen path real hardware takes (and hid the G3b font-order bug).
    // The screens are an exclusive-keyboard overlay, so this must never be the default for a preview on a live desktop.
    readonly property bool use_screens: !Greeter.preview || Quickshell.env("QS_GREETER_SCREENS") === "1"

    Variants {
        // Variants builds its windows in componentComplete, before Fonts' onCompleted registers the files, and the MGS2 title measures
        // its text once; building the screens only after `ready` keeps it from locking in a fallback font.
        model: root.use_screens && bundled_fonts.ready ? Quickshell.screens : []

        delegate: Component {
            PanelWindow {
                id: panel
                required property var modelData
                screen: modelData
                color: Theme.bg_shadow
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "qs-greeter"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: panel.modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                // Once per start, so a test can tell whether the skin was built before or after the fonts registered.
                Component.onCompleted: if (panel.modelData === Quickshell.screens[0]) console.log("greeter: fonts_ready=" + bundled_fonts.ready + " at screen build")

                GreeterSurface {
                    anchors.fill: parent
                }
            }
        }
    }

    LazyLoader {
        active: !root.use_screens

        FloatingWindow {
            title: "Greeter preview"
            implicitWidth: 1600
            implicitHeight: 900
            color: Theme.bg_shadow

            GreeterSurface {
                anchors.fill: parent
            }
        }
    }

}
