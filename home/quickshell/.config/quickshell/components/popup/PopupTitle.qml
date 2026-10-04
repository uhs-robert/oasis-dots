// home/quickshell/.config/quickshell/components/popup/PopupTitle.qml
import QtQuick
import "../../theme"
import ".."

Item {
    id: root

    required property var st
    required property string title
    required property string shown_title
    required property string title_value
    required property string popup_name
    required property bool passive
    required property bool has_title
    required property bool banded
    required property real band_height
    required property bool lcd
    required property real device_side
    required property real device_top
    required property bool wanted
    required property Item layer_item
    readonly property real tab_height: title_tab.height

    anchors.fill: parent

    Loader {
        active: root.has_title && root.banded
        x: root.st.inset_pad + root.st.frame_border_width
        y: x
        width: parent.width - x * 2
        height: root.band_height
        sourceComponent: TitleStrip {
            title: root.title
            readout_value: root.title_value
            closable: !root.passive
        }
    }

    Rectangle {
        id: title_tab
        visible: root.has_title && !root.banded && !root.st.border_title
        x: (root.st.fade_fills ? root.st.frame_border_width : 0) + root.st.inset_pad + root.st.lcd_margin * 2 + root.device_side
        y: (root.st.fade_fills ? root.st.frame_border_width : 0) + root.st.inset_pad + root.st.lcd_margin * 2 + root.device_top
        readonly property real reticle_space: root.st.title_reticle.a > 0 ? title_text.implicitHeight + 4 : 0
        readonly property real lead_space: title_tab.reticle_space + title_index.space
        width: root.st.fade_fills ? parent.width - root.st.frame_border_width * 2 : Math.min(Math.ceil(Math.max(title_metrics.width, title_metrics.advanceWidth)) + 20 + title_tab.lead_space, parent.width - title_tab.x * 2)
        height: Math.max(title_text.implicitHeight, title_index.space > 0 ? title_index.implicitHeight : 0) + 4
        color: root.st.fade_fills ? "transparent" : root.st.title_bg

        Reticle {
            visible: title_tab.reticle_space > 0
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: title_tab.reticle_space - 4
            height: width
            color: root.st.title_reticle
            center_color: root.st.caret_color
        }

        FadeFill {
            visible: root.st.fade_fills
            fill: root.st.title_bg
        }

        TitleIndex {
            id: title_index
            x: 10 + title_tab.reticle_space
            anchors.verticalCenter: parent.verticalCenter
            st: root.st
            name: root.popup_name
        }

        TextMetrics {
            id: title_metrics
            font: title_text.font
            text: title_text.text
        }

        Text {
            id: title_text
            anchors.centerIn: root.st.fade_fills ? undefined : parent
            anchors.horizontalCenterOffset: title_tab.lead_space / 2
            x: 10 + title_tab.lead_space
            y: (parent.height - height) / 2
            width: Math.min(Math.ceil(Math.max(title_metrics.width, title_metrics.advanceWidth)), parent.width - 20 - title_tab.lead_space)
            elide: Text.ElideRight
            text: root.st.title_prefix + root.shown_title + (Style.caret_phase ? root.st.title_suffix : " ".repeat(root.st.title_suffix.length))
            color: root.st.title_fg
            font.family: root.st.title_font_family
            font.pixelSize: root.st.title_size > 0 ? root.st.title_size : root.st.fs(-2)
            font.weight: root.st.title_weight > 0 ? root.st.title_weight : root.st.title_font_family === root.st.font_family ? Font.Bold : Font.Normal
            font.letterSpacing: root.st.title_spacing
        }
    }

    Text {
        id: title_readout
        // Dropped on narrow popups rather than drawn over the title.
        visible: root.has_title && root.st.title_readout !== "" && title_tab.x + (root.st.fade_fills ? 10 + title_tab.lead_space + title_text.implicitWidth : title_tab.width) + 12 <= parent.width - anchors.rightMargin - implicitWidth
        anchors.right: parent.right
        anchors.rightMargin: (root.lcd ? root.st.lcd_margin * 2 : 12) + root.st.inset_pad + root.device_side
        y: title_tab.y + (title_tab.height - height) / 2
        text: root.st.title_readout.replace("{code}", root.title.slice(0, 3))
        color: root.st.title_readout_fg.a > 0 ? root.st.title_readout_fg : root.st.text_muted
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-5)
        font.letterSpacing: 1
    }

    // Plain sentence-case titles carry the live title value at the right, like a status line.
    Text {
        visible: root.has_title && !root.banded && root.st.title_status && !root.st.border_title && root.st.title_readout === "" && root.title_value !== "" && title_tab.x + title_tab.width + 12 <= parent.width - anchors.rightMargin - implicitWidth
        anchors.right: parent.right
        anchors.rightMargin: title_readout.anchors.rightMargin + 4
        y: title_tab.y + (title_tab.height - height) / 2
        text: root.title_value
        color: root.st.text_muted
        font.family: root.st.mono_font
        font.pixelSize: root.st.fs(-3)
    }

    Loader {
        active: root.has_title && !root.banded && !root.passive && root.st.console_views === "ps2"
        visible: title_tab.x + title_tab.width + 10 <= x
        anchors.right: parent.right
        anchors.rightMargin: title_readout.anchors.rightMargin
        y: title_tab.y + (title_tab.height - height) / 2
        source: active ? "../ps2/AnalogLed.qml" : ""
        onLoaded: item.lit = Qt.binding(() => root.wanted && root.layer_item.Window.active)
    }

    Rectangle {
        visible: root.has_title && root.st.title_trail.a > 0 && width > 8
        x: title_tab.x + (root.st.fade_fills ? 10 + title_tab.lead_space + title_text.implicitWidth + 12 : title_tab.width)
        y: title_tab.y + Math.round(title_tab.height / 2)
        width: (title_readout.visible ? title_readout.x - 12 : parent.width - title_readout.anchors.rightMargin) - x
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.st.title_trail }
            GradientStop { position: 1; color: Qt.alpha(root.st.title_trail, 0) }
        }
    }

    Rectangle {
        visible: root.has_title && root.st.title_rule.a > 0
        x: title_tab.x
        y: title_tab.y + title_tab.height + 2
        width: parent.width - title_tab.x * 2
        height: 1
        color: root.st.title_rule
    }
}
