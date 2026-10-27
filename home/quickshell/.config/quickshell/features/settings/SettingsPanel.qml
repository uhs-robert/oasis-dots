import QtQuick
import qs.theme

// The docked panel beside (or, when `stacked`, under) a settings pane. The pane's help card goes into `help_host`
// and a section's preview into `preview_host`; a pane with no preview gives the help card the whole panel.
// Only `st` tokens: a style restyles the panel through them, never by branching here.
Item {
    id: root

    property var st: Style
    // Help and preview side by side instead of one above the other, for a panel docked under the rows.
    property bool stacked: false
    // What the help card sits on and how tall its scroll fade is (the ScrollCue over it).
    property color fade_top: root.st.frame_color
    property color fade_bottom: root.st.frame_color
    property real fade_height: Style.px(20)
    readonly property Item help_host: help_slot
    readonly property Item preview_host: preview_slot
    readonly property real gap: Style.px(12)
    // childrenRect counts hidden children, and the help card hides while a list is open.
    function shown_height(host) {
        let h = 0;
        for (const child of host.children) if (child.visible) h = Math.max(h, child.y + child.height);
        return h;
    }
    readonly property real help_content: root.shown_height(help_slot)
    readonly property real preview_height: root.shown_height(preview_slot)
    readonly property bool has_preview: root.preview_height > 0

    // A preview is pinned to the panel's top (or its right half when stacked) and the help card takes the rest, so
    // neither the focused row's text nor an open list hiding the card moves the preview.
    readonly property bool help_beside: root.stacked && root.has_preview

    function reset_help_scroll() {
        help_flick.contentY = 0;
    }

    Flickable {
        id: help_flick
        objectName: "help"
        x: 0
        y: root.stacked || !root.has_preview ? 0 : root.preview_height + root.gap
        width: root.help_beside ? Math.round((root.width - root.gap) / 2) : root.width
        height: Math.max(0, root.height - help_flick.y)
        clip: true
        contentWidth: width
        contentHeight: root.help_content
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: help_slot
            width: help_flick.width
            height: root.help_content
        }
    }

    ScrollCue {
        target: help_flick
        st: root.st
        top_color: root.fade_top
        bottom_color: root.fade_bottom
        fade_height: root.fade_height
    }

    Item {
        id: preview_slot
        x: root.help_beside ? help_flick.width + root.gap : 0
        y: 0
        width: root.width - x
        // An oversized preview is cut at the panel's edge rather than drawn past the drawer.
        height: Math.min(root.preview_height, root.height - y)
        clip: true
    }
}
