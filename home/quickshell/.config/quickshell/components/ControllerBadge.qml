// home/quickshell/.config/quickshell/components/ControllerBadge.qml
import QtQuick
import "../theme"
import "KeyHints.js" as KeyHints

// A key drawn as the console's buttons (components/<console>/<Console>Button.qml); unmapped parts stay key text.
Row {
    id: root

    property string controller: ""
    property string key: ""
    // The hint's action, which decides Esc's button (KeyHints.button_for).
    property string desc: ""
    property real size: 14
    property color text_color: Style.key_fg
    property string font_family: Style.mono_font
    property real font_size: Style.fs(-5)
    readonly property var parts: KeyHints.controller_parts(root.controller, root.key, root.desc)
    readonly property string button_url: root.controller === "" ? "" : Qt.resolvedUrl(root.controller + "/" + root.controller.charAt(0).toUpperCase() + root.controller.slice(1) + "Button.qml")

    spacing: 2

    Repeater {
        model: root.parts

        Row {
            id: part
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

            Loader {
                active: !!part.modelData.button
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                source: active ? root.button_url : ""
                onLoaded: {
                    item.button = Qt.binding(() => part.modelData.button || "");
                    item.size = Qt.binding(() => root.size);
                }
            }

            Text {
                visible: !part.modelData.button
                anchors.verticalCenter: parent.verticalCenter
                text: KeyHints.with_glyphs(part.modelData.text || "")
                color: root.text_color
                font.family: root.font_family
                font.pixelSize: root.font_size
            }
        }
    }
}
