// home/quickshell/.config/quickshell/components/MenuFooter.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "KeyHints.js" as KeyHints

// The key hint line under a popup; some styles rule it off with a dashed line.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property string text: ""
    property bool wrap: root.st.footer_wrap
    property bool centered: false
    // Tabs that show their number already teach "1-N select".
    readonly property string filtered_text: root.st.tab_keys ? root.text.split(" · ").filter(g => !/^1-\d select$/.test(g)).join(" · ") : root.text
    readonly property string shown_text: KeyHints.with_glyphs(root.filtered_text)
    readonly property int rule_gap: root.st.footer_rule ? 5 : 0
    readonly property var groups: KeyHints.parse(root.shown_text)
    // While the enclosing popup searches, its query line takes this footer's place at the same height.
    readonly property var popup: {
        for (let p = root.parent; p; p = p.parent) {
            if (p.search_popup !== undefined) return p.search_popup;
        }
        return null;
    }
    readonly property bool searching: !!root.popup && root.popup.search_shown
    readonly property int match_count: root.searching ? root.popup.search_matches.length : 0
    readonly property int match_position: root.searching ? root.popup.search_matches.indexOf(root.popup.search_cursor) : -1

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
        opacity: root.searching ? 0 : 1
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

    Item {
        visible: root.searching
        y: root.rule_gap
        width: root.width
        height: query_text.implicitHeight

        Text {
            id: slash_text
            text: "/"
            color: root.st.footer_key_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 4
        }

        Text {
            id: query_text
            x: slash_text.implicitWidth + 2
            width: Math.min(implicitWidth, Math.max(0, status_text.x - x - 10))
            elide: Text.ElideLeft
            text: root.searching ? root.popup.search_query : ""
            color: root.st.text_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 4
        }

        Rectangle {
            visible: root.searching && root.popup.search_typing
            opacity: Style.caret_phase ? 1 : 0
            x: query_text.x + query_text.width + 1
            y: 1
            width: 2
            height: Math.max(0, query_text.height - 2)
            color: root.st.caret_color
        }

        Text {
            id: status_text
            anchors.right: parent.right
            text: !root.searching || root.popup.search_query === "" ? "" : root.match_count === 0 ? "no match" : (root.match_position >= 0 ? root.match_position + 1 : "-") + "/" + root.match_count
            color: root.match_count === 0 ? Theme.warning : root.st.footer_fg
            font.family: root.st.font_family
            font.pixelSize: root.st.font_size - 4
            font.capitalization: root.st.label_caps ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: root.st.label_spacing
        }
    }
}
