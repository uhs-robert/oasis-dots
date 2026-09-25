// home/quickshell/.config/quickshell/components/KeyHelp.qml
import QtQuick
import "../theme"
import "../services"
import "KeyHints.js" as KeyHints

// A popup's full key list, drawn over its content at the same size.
Item {
    id: root

    readonly property var st: Style.for_item(root)

    property string text: ""
    property int tab_count: 0
    property bool has_views: false
    property bool searchable: false
    signal back()

    readonly property var own_entries: KeyHints.parse(root.text).filter(g => !(g.key === "[ ]" && g.desc === "tabs") && !(/^1-\d$/.test(g.key) && g.desc === "select") && !(g.key === "q" && g.desc === "close"))
    readonly property var own_keys: root.own_entries.reduce((keys, g) => keys.concat(g.key.split("/")), [])
    readonly property var general_entries: {
        const e = [];
        if (root.tab_count > 0) {
            e.push({ key: "[ ]", desc: "tabs" });
            e.push({ key: root.tab_count > 1 ? "1-" + Math.min(9, root.tab_count) : "1", desc: "select" });
        }
        if (root.has_views) e.push({ key: "Tab", desc: "views" });
        if (root.searchable) e.push({ key: "/", desc: "search" }, { key: "n/N", desc: "next/prev match" });
        e.push({ key: "Ctrl+h/l", desc: "prev/next module" });
        e.push({ key: "?", desc: "help" }, { key: "Backspace", desc: Popups.back_name !== "" ? "back to " + Popups.back_name : "back" }, { key: "q/Esc", desc: "close" });
        return e.filter(g => root.own_keys.indexOf(g.key) < 0);
    }

    readonly property real key_column: {
        if (root.st.controller !== "") return Math.min(list.width * 0.5, Math.max(key_metrics.height + 2, measure.implicitWidth));
        const h = key_metrics.height + 2;
        let w = 0;
        for (const g of root.own_entries.concat(root.general_entries)) w = Math.max(w, key_metrics.advanceWidth(KeyHints.with_glyphs(g.key)));
        return Math.min(list.width * 0.45, Math.max(h, w + 8));
    }
    // Controller rows share the tallest badge's height so button and key rows keep one pitch.
    readonly property real pad_row_height: {
        let h = 0;
        for (let i = 0; i < measure.children.length; i++) h = Math.max(h, measure.children[i].height || 0);
        return h;
    }
    readonly property real step: desc_metrics.height * 2
    readonly property real max_y: Math.max(0, flick.contentHeight - flick.height)
    property double last_g_ms: 0

    function scroll_to(y) {
        flick.contentY = Math.max(0, Math.min(root.max_y, y));
    }

    onVisibleChanged: if (visible) flick.contentY = 0

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Question || event.text === "?" || event.key === Qt.Key_Backspace) {
            root.back();
        } else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) {
            Popups.close();
        } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.scroll_to(flick.contentY + root.step);
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.scroll_to(flick.contentY - root.step);
        } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            root.scroll_to(root.max_y);
        } else if (event.key === Qt.Key_G) {
            const now_ms = Date.now();
            if (now_ms - root.last_g_ms < 500) {
                root.last_g_ms = 0;
                root.scroll_to(0);
            } else {
                root.last_g_ms = now_ms;
            }
        }
        event.accepted = true;
    }

    FontMetrics {
        id: key_metrics
        font.family: root.st.mono_font
        font.pixelSize: root.st.fs(-5)
        font.bold: root.st.mono_font === root.st.font_family
    }

    FontMetrics {
        id: desc_metrics
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }

    // Keeps clicks, hover and wheel off the hidden content underneath.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    // Sizes the key column from the badges as drawn, controller buttons included.
    Column {
        id: measure
        opacity: 0
        enabled: false

        Repeater {
            model: root.st.controller !== "" ? root.own_entries.concat(root.general_entries) : []

            KeyBadge {
                required property var modelData
                with_key: true
                key: KeyHints.with_glyphs(modelData.key)
                desc: modelData.desc
            }
        }
    }

    Component {
        id: help_row_component

        Item {
            id: help_row
            required property var modelData
            width: list.width
            height: Math.max(root.pad_row_height, badge_clip.height, desc_text.implicitHeight)

            Item {
                id: badge_clip
                y: Math.max(0, (Math.max(desc_metrics.height, root.pad_row_height) - height) / 2)
                width: root.key_column
                height: badge.height
                clip: badge.width > width

                KeyBadge {
                    id: badge
                    with_key: true
                    key: KeyHints.with_glyphs(help_row.modelData.key)
                    desc: help_row.modelData.desc
                }
            }

            Text {
                id: desc_text
                x: root.key_column + 8
                y: Math.max(0, (root.pad_row_height - desc_metrics.height) / 2)
                width: Math.max(0, help_row.width - x)
                text: help_row.modelData.desc
                wrapMode: Text.Wrap
                color: root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
                font.capitalization: root.st.label_caps ? Font.AllUppercase : Font.MixedCase
                font.letterSpacing: root.st.label_spacing
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 12
        clip: true
        contentWidth: width
        contentHeight: list.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: flick.width - 6
            spacing: 5

            Repeater {
                model: root.own_entries
                delegate: help_row_component
            }

            Item {
                visible: root.own_entries.length > 0
                width: list.width
                height: 4
            }

            MenuSection {
                label: "General"
            }

            Repeater {
                model: root.general_entries
                delegate: help_row_component
            }
        }
    }

    Rectangle {
        visible: flick.contentHeight > flick.height
        x: flick.x + flick.width - width
        y: flick.y + flick.visibleArea.yPosition * flick.height
        width: 2
        height: flick.visibleArea.heightRatio * flick.height
        color: root.st.text_muted
    }
}
