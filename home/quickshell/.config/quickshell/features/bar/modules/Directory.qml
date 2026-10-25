import QtQuick
import qs.theme
import qs.features.bar

// The focused window's app and working directory in an island. A lualine bar draws the same segment in section c
// itself, so this stays hidden there.
BarModule {
    id: root
    module_name: "directory"
    has_popup: false
    wash: false

    shown: !(Style.bar_lualine && !root.vertical) && segment.has_content
    implicitWidth: root.shown ? segment.implicitWidth : 0
    implicitHeight: segment.implicitHeight

    WindowSegment {
        id: segment
        screen_name: root.screen_name
        bar_height: root.bar_height
        padding: 0
    }
}
