// /etc/greetd/quickshell/shell.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "theme"

// The login screen: the lock skin in the user's lock style, fullscreen under greetd, in a window as a preview otherwise.
ShellRoot {
    id: root

    Fonts {}

    Variants {
        model: Greeter.preview ? [] : Quickshell.screens

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

                GreeterSurface {
                    anchors.fill: parent
                }
            }
        }
    }

    LazyLoader {
        active: Greeter.preview

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

    Component.onCompleted: Greeter.mark_ready()
}
