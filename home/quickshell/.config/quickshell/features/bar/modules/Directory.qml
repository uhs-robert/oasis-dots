import QtQuick
import qs.theme
import qs.features.bar
import qs.features.popups

// The focused window's app and working directory in an island. A lualine bar draws the same segment in section c
// itself (Bar.qml drops this entry there), and the segment is too wide for a side bar's column.
BarModule {
    id: root
    module_name: "directory"
    has_popup: false
    wash: false

    shown: !Style.bar_lualine && !root.vertical && segment.has_content
    implicitWidth: root.shown ? segment.implicitWidth : 0
    implicitHeight: segment.implicitHeight
    // Set by Bar.qml: the most this module may take before its island crowds the next one.
    property real room: Infinity
    tooltip_text: segment.tooltip_text
    onTooltip_textChanged: if (root.hovered) Tooltip.show(root, root.tooltip_text, root.tooltip_title)

    WindowSegment {
        id: segment
        screen_name: root.screen_name
        bar_height: root.bar_height
        max_width: root.room
        padding: 0
    }
}
