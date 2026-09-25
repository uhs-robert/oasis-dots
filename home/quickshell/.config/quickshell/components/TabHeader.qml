// home/quickshell/.config/quickshell/components/TabHeader.qml
import QtQuick
import "../theme"

// A title strip with a tab-cut band (panel id and name), a hatch block and a right-hand readout.
Item {
    id: root

    property var st: Style.for_item(root)
    property string title: ""
    property string panel_id: ""
    property string readout: ""
    property string readout_value: ""
    // Overrides the title and band underline colour when set, e.g. with the active submap's.
    property color accent: "transparent"
    readonly property real cut: root.st.frame_cut
    readonly property color line: root.st.frame_line.a > 0 ? root.st.frame_line : root.st.frame_border_color
    readonly property real band_width: Math.min(band_row.implicitWidth + 42, root.width)
    // The narrowest width that shows the whole title; mirrors title_text's width limit.
    readonly property real min_width: band_row.x + 40 + (root.panel_id !== "" ? 30 : 0) + title_text.implicitWidth

    implicitHeight: Math.max(26, title_text.implicitHeight + 8)

    CutBox {
        anchors.fill: parent
        cut_tl: root.cut
        fill: Qt.alpha(root.line, root.line.a * 0.38)
        fill_end: "transparent"
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.line
    }

    CutBox {
        width: root.band_width
        height: parent.height
        cut_tl: root.cut
        cut_br: Math.min(14, root.height)
        fill: root.st.title_band
        fill_end: Qt.alpha(root.st.title_band, 0.5)
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: Math.max(0, root.band_width - 2)
        height: 2
        color: root.accent.a > 0 ? root.accent : root.st.tab_underline.a > 0 ? root.st.tab_underline : root.st.caret_color
    }

    Row {
        id: band_row
        x: Math.max(18, root.cut + 4)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            visible: root.panel_id !== ""
            anchors.baseline: title_text.baseline
            text: root.panel_id
            color: root.st.text_accent
            font.family: root.st.mono_font
            font.pixelSize: root.st.fs(-4)
        }

        Text {
            id: title_text
            width: Math.max(0, Math.min(implicitWidth, root.width - band_row.x - 40 - (root.panel_id !== "" ? 30 : 0)))
            elide: Text.ElideRight
            text: root.title
            color: root.accent.a > 0 ? root.accent : root.st.title_fg
            font.family: root.st.title_font_family
            font.pixelSize: root.st.fs(-1)
            font.bold: true
            font.letterSpacing: root.st.title_spacing
        }
    }

    Hazard {
        visible: root.width - root.band_width - readout_text.implicitWidth > 60
        x: root.band_width + 4
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: parent.height - 18
        stripe: root.line
        tile: 4
        line: 1.2
    }

    Text {
        id: readout_text
        visible: root.readout !== "" && root.band_width + implicitWidth + 16 <= root.width
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        textFormat: Text.StyledText
        text: root.readout + (root.readout_value !== "" ? " <font color='" + root.st.text_strong + "'>" + root.readout_value + "</font>" : "")
        color: root.st.title_readout_fg.a > 0 ? root.st.title_readout_fg : root.st.text_muted
        font.family: root.st.mono_font
        font.pixelSize: root.st.fs(-5)
        font.letterSpacing: 1.4
    }
}
