// home/quickshell/.config/quickshell/components/MenuFooter.qml
import QtQuick
import QtQuick.Layouts
import "../theme"
import "oasis" as Oasis
import "KeyHints.js" as KeyHints

// The key hint line under a popup; some styles rule it off with a dashed line.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property string text: ""
    property bool wrap: root.st.footer_wrap
    property bool centered: false
    readonly property int text_px: root.st.footer_size > 0 ? root.st.footer_size : root.st.fs(-4)
    readonly property int small_px: root.st.footer_size > 0 ? root.st.footer_size : root.st.fs(-5)
    readonly property bool arrows: root.st.footer_arrow !== ""
    // Tabs that show their number already teach "1-N select".
    readonly property string filtered_text: root.st.tab_keys ? root.text.split(" · ").filter(g => !/^1-\d select$/.test(g)).join(" · ") : root.text
    readonly property int rule_gap: root.st.footer_rule ? (root.st.footer_moon ? 11 : root.st.footer_tanks ? 8 : 5) : 0
    readonly property var groups: KeyHints.parse(root.filtered_text)
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
    // Vim-modal popups (search_starts_open) show an INSERT chip and a mode-specific hint in the query line.
    readonly property bool modal: !!root.popup && root.popup.search_starts_open

    Layout.minimumWidth: 0
    implicitWidth: hint.childrenRect.width
    implicitHeight: hint.childrenRect.height + root.rule_gap
    clip: !root.wrap

    Loader {
        active: root.st.footer_rule && root.st.footer_moon
        width: parent.width
        sourceComponent: Oasis.MoonRule {
            color: root.st.footer_rule_color
        }
    }

    Rectangle {
        visible: root.st.footer_rule && root.st.footer_rule_solid && !root.st.footer_moon
        width: parent.width
        height: 1
        color: root.st.footer_rule_color
    }

    Row {
        visible: root.st.footer_rule && !root.st.footer_rule_solid
        width: parent.width
        spacing: 3
        clip: true

        // footer_tanks draws the rule as a row of energy-tank squares.
        Repeater {
            model: root.st.footer_rule && !root.st.footer_rule_solid ? Math.max(0, Math.ceil(root.width / (root.st.footer_tanks ? 6 : 7))) : 0

            Rectangle {
                width: root.st.footer_tanks ? 3 : 4
                height: root.st.footer_tanks ? 3 : 1
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
        spacing: root.st.footer_separator === "" ? (root.st.footer_size > 0 ? Math.round(root.text_px * 1.8) : 10) : 0

        Repeater {
            model: root.groups

            Row {
                id: group
                required property var modelData
                required property int index
                readonly property bool pad: root.st.controller !== "" && KeyHints.controller_parts(root.st.controller, group.modelData.key, group.modelData.desc).length > 0
                spacing: root.st.footer_size > 0 && !root.arrows ? Math.round(root.text_px * 0.75) : 4

                Loader {
                    active: group.pad
                    visible: active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: ControllerBadge {
                        controller: root.st.controller
                        key: group.modelData.key
                        desc: group.modelData.desc
                        size: Math.round(desc_text.implicitHeight)
                        text_color: root.st.footer_key_fg
                        font_family: root.st.font_family
                        font_size: root.text_px
                    }
                }

                Text {
                    id: key_text
                    readonly property bool capped: root.st.footer_key_bg.a > 0
                    visible: !group.pad
                    height: desc_text.implicitHeight
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: key_text.capped ? 4 : 0
                    rightPadding: key_text.capped ? 4 : 0
                    text: KeyHints.with_glyphs(parent.modelData.key)
                    color: root.st.footer_key_fg
                    font.family: key_text.capped ? root.st.mono_font : root.st.font_family
                    font.pixelSize: root.text_px

                    Rectangle {
                        visible: key_text.capped
                        z: -1
                        anchors.fill: parent
                        anchors.topMargin: 1
                        anchors.bottomMargin: 1
                        radius: Style.radius(3)
                        color: root.st.footer_key_bg
                        border.width: root.st.rounded ? 1 : 0
                        border.color: root.st.key_border
                    }
                }

                Text {
                    visible: root.arrows && !group.pad
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.st.footer_arrow
                    color: root.st.text_muted
                    font.family: root.st.font_family
                    font.pixelSize: root.small_px
                }

                Text {
                    id: desc_text
                    anchors.verticalCenter: parent.verticalCenter
                    text: KeyHints.with_glyphs(parent.modelData.desc) + (parent.index < root.groups.length - 1 ? root.st.footer_separator : "")
                    color: root.st.footer_fg
                    font.family: root.st.font_family
                    font.pixelSize: root.text_px
                    font.italic: root.st.footer_italic
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
            id: mode_chip
            visible: root.modal
            text: "INSERT"
            color: root.st.text_accent
            font.family: root.st.font_family
            font.pixelSize: root.text_px
            font.bold: true
        }

        Text {
            id: slash_text
            x: root.modal ? mode_chip.implicitWidth + 6 : 0
            text: "/"
            color: root.st.footer_key_bg.a > 0 ? root.st.footer_key_bg : root.st.footer_key_fg
            font.family: root.st.font_family
            font.pixelSize: root.text_px
        }

        Text {
            id: query_text
            x: slash_text.x + slash_text.implicitWidth + 2
            width: Math.min(implicitWidth, Math.max(0, status_text.x - x - 10))
            elide: Text.ElideLeft
            text: root.searching ? root.popup.search_query : ""
            color: root.st.text_fg
            font.family: root.st.font_family
            font.pixelSize: root.text_px
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
            text: !root.searching ? "" : root.popup.search_query === "" ? (root.modal ? KeyHints.with_glyphs("Enter") + " apply" : "") : root.match_count === 0 ? "no match" : (root.match_position >= 0 ? root.match_position + 1 : "-") + "/" + root.match_count
            color: root.searching && root.popup.search_query !== "" && root.match_count === 0 ? Theme.warning : root.st.footer_fg
            font.family: root.st.font_family
            font.pixelSize: root.text_px
            font.capitalization: root.st.label_caps ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: root.st.label_spacing
        }
    }
}
