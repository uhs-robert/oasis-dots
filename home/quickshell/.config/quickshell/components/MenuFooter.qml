// home/quickshell/.config/quickshell/components/MenuFooter.qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// The key hint line under a popup; some styles rule it off with a dashed line.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property string text: ""
    property bool wrap: root.st.footer_wrap
    property bool centered: false
    // Tabs that show their number already teach "1-N select".
    readonly property string filtered_text: root.st.tab_keys ? root.text.split(" · ").filter(g => !/^1-\d select$/.test(g)).join(" · ") : root.text
    readonly property var key_glyphs: ({ Enter: String.fromCodePoint(0xF0311), Esc: String.fromCodePoint(0xF12B7), Tab: String.fromCodePoint(0xF0312), space: String.fromCodePoint(0xF1050), Backspace: String.fromCodePoint(0xF030D) })
    readonly property string shown_text: root.filtered_text.replace(/\b(Enter|Esc|Tab|space|Backspace)\b/g, k => root.key_glyphs[k])
    readonly property int rule_gap: root.st.footer_rule ? 5 : 0

    // Each "key desc" group; "[ ]" is the one key that contains a space.
    readonly property var groups: root.shown_text === "" ? [] : root.shown_text.split(" · ").map(g => {
        const key = g.startsWith("[ ]") ? "[ ]" : g.split(" ")[0];
        return { key: key, desc: g.slice(key.length).trim() };
    })

    Layout.minimumWidth: 0
    implicitWidth: hint.childrenRect.width
    implicitHeight: hint.childrenRect.height + root.rule_gap
    clip: !root.wrap

    Row {
        visible: root.st.footer_rule
        width: parent.width
        spacing: 3
        clip: true

        Repeater {
            model: root.st.footer_rule ? Math.max(0, Math.ceil(root.width / 7)) : 0

            Rectangle {
                width: 4
                height: 1
                color: root.st.footer_rule_color
            }
        }
    }

    Flow {
        id: hint
        x: root.centered ? Math.max(0, (root.width - childrenRect.width) / 2) : 0
        y: root.rule_gap
        width: root.wrap && !root.centered ? parent.width : 100000

        Repeater {
            model: root.groups

            Row {
                required property var modelData
                required property int index
                spacing: 4

                Text {
                    height: desc_text.implicitHeight
                    verticalAlignment: Text.AlignVCenter
                    text: parent.modelData.key
                    color: root.st.footer_key_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 4
                }

                Text {
                    id: desc_text
                    text: parent.modelData.desc + (parent.index < root.groups.length - 1 ? " · " : "")
                    color: root.st.footer_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.st.font_size - 4
                    font.capitalization: root.st.label_caps ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: root.st.label_spacing
                }
            }
        }
    }
}
