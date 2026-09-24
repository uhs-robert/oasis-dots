// home/quickshell/.config/quickshell/components/MenuFooter.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// The key hint line under a popup; some styles rule it off with a dashed line.
Item {
    id: root

    property string text: ""
    property bool wrap: Style.footer_wrap
    // Tabs that show their number already teach "1-N select".
    readonly property string shown_text: Style.tab_keys ? root.text.split(" · ").filter(g => !/^1-\d select$/.test(g)).join(" · ") : root.text
    readonly property int rule_gap: Style.footer_rule ? 5 : 0

    Layout.minimumWidth: 0
    implicitWidth: hint.implicitWidth
    implicitHeight: hint.implicitHeight + root.rule_gap

    Row {
        visible: Style.footer_rule
        width: parent.width
        spacing: 3
        clip: true

        Repeater {
            model: Style.footer_rule ? Math.max(0, Math.ceil(root.width / 7)) : 0

            Rectangle {
                width: 4
                height: 1
                color: Style.footer_rule_color
            }
        }
    }

    Text {
        id: hint
        y: root.rule_gap
        width: parent.width
        elide: root.wrap ? Text.ElideNone : Text.ElideRight
        wrapMode: root.wrap ? Text.WordWrap : Text.NoWrap
        // Wrapped hints break only between groups, never inside "j/k move".
        text: root.wrap ? root.shown_text.split(" · ").map(g => g.replace(/ /g, "\u00a0").replace(/\//g, "/\u2060")).join("\u00a0· ") : root.shown_text
        color: Style.footer_fg
        font.family: Style.font_family
        font.pixelSize: Style.font_size - 4
    }
}
