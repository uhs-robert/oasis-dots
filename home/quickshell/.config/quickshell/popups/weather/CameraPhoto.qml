// home/quickshell/.config/quickshell/popups/weather/CameraPhoto.qml
import QtQuick
import "../../components"
import "../../theme"
import "../../services"
import "PixelArt.js" as PixelArt

// One day as a framed Game Boy Camera photo with its hi/lo dot bar, temperatures and rain chance.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property bool selected: false
    property real scale_min: 0
    property real scale_max: 1
    // Narrowest column width in the strip, so every photo picks the same scale.
    property real slot_w: root.width

    // Three 2px selection rings plus 4px inner padding, reserved even unselected so sizing never jumps.
    readonly property int box_pad: 10
    readonly property real avail_w: root.slot_w - 2 * root.box_pad
    readonly property real avail_h: root.height - 2 * root.box_pad

    // Silkscreen sits on an 8px grid, so step up by whole grid units while the widest label and temp pair still fit.
    readonly property int text_size: {
        for (const size of [32, 24]) {
            if (Math.max(root.label_w(size), root.temp_w(size)) <= root.avail_w - 2 && root.avail_h >= 6 * size + 110) return size;
        }
        return Style.font_size;
    }
    // The high reads one grid step larger when a single stacked temperature has the width for it.
    readonly property int hi_size: root.text_size < 32 && root.temp_w(root.text_size + 8) <= root.avail_w - 2 ? root.text_size + 8 : root.text_size
    // Rough label/temp/pop row height, used only to budget the sprite scale; the real gap is filled below.
    readonly property real text_row_h: root.text_size + 6
    readonly property int width_pixel: Math.max(1, Math.floor((root.avail_w - 18) / 24))
    readonly property int height_pixel: Math.max(1, Math.floor((root.avail_h - 4 * root.text_row_h - 46) / 20))
    // Largest integer scale of the 24x18 photo that fits both the column width and the available height.
    readonly property int pixel: Math.max(1, Math.min(6, Math.min(root.width_pixel, root.height_pixel)))

    // One-shot hop offset applied to the photo frame when the selection lands here; never loops.
    property int hop_offset: 0

    onSelectedChanged: {
        if (root.selected && Popups.open_name === "weather") hop_anim.restart();
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "weather") hop_anim.stop();
        }
    }

    SequentialAnimation {
        id: hop_anim
        PropertyAction { target: root; property: "hop_offset"; value: -4 }
        PauseAnimation { duration: 100 }
        PropertyAction { target: root; property: "hop_offset"; value: -2 }
        PauseAnimation { duration: 100 }
        PropertyAction { target: root; property: "hop_offset"; value: 0 }
    }

    // Space left over after the photo, dot bar and labels take their natural size, spread across the gaps between them.
    readonly property real content_h: label_row.height + photo_box.height + dot_bar.height + temp_row.height + pop_text.height
    readonly property real fill_spacing: Math.max(3, (root.avail_h - root.content_h) / 4)

    function label_w(size: int): real {
        return arrow_metrics.advanceWidth + 2 + (size === 32 ? label_32.advanceWidth : label_24.advanceWidth);
    }

    function temp_w(size: int): real {
        return (size === 32 ? temp_32.advanceWidth : size === 24 ? temp_24.advanceWidth : 0) + Math.max(3, Math.round(size / 4)) + 2;
    }

    TextMetrics { id: arrow_metrics; font.family: Style.font_family; font.pixelSize: Style.font_size; text: "▶" }
    TextMetrics { id: label_24; font.family: Style.font_family; font.pixelSize: 24; text: "TODAY" }
    TextMetrics { id: label_32; font.family: Style.font_family; font.pixelSize: 32; text: "TODAY" }
    // The week's extremes share one scale across columns, so every photo picks the same size.
    readonly property string widest_temp: {
        const a = String(Math.round(root.scale_min)), b = String(Math.round(root.scale_max));
        return a.length > b.length ? a : b;
    }
    TextMetrics { id: temp_24; font.family: Style.font_family; font.pixelSize: 24; text: root.widest_temp }
    TextMetrics { id: temp_32; font.family: Style.font_family; font.pixelSize: 32; text: root.widest_temp }

    // Pokémon-menu double border around the whole column, sized to the padding reserved above.
    PixelBox {
        visible: root.selected
        anchors.fill: parent
        fill: "transparent"
        rings: [Style.shade_3, "transparent", Style.shade_3]
    }

    Column {
        x: Math.round((root.width - width) / 2)
        y: root.box_pad + Math.round((root.avail_h - height) / 2)
        spacing: root.fill_spacing

        Row {
            id: label_row
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Text {
                visible: root.selected
                anchors.verticalCenter: parent.verticalCenter
                text: "▶"
                color: Style.shade_3
                font.family: Style.font_family
                font.pixelSize: Style.font_size
            }

            Text {
                text: root.day ? (root.day_index === 0 ? "TODAY" : root.day.weekday.toUpperCase()) : ""
                color: root.selected ? Style.shade_3 : Style.shade_2
                font.family: Style.font_family
                font.pixelSize: root.text_size
            }
        }

        Item {
            id: photo_box
            anchors.horizontalCenter: parent.horizontalCenter
            width: photo.width + 18
            height: photo.height + 18
            transform: Translate { y: root.hop_offset }

            PixelBox {
                anchors.fill: parent
                fill: Style.shade_3
                rings: root.selected ? [Style.shade_0, Style.shade_3, Style.shade_0] : ["transparent", Style.shade_2, Style.shade_0]
            }

            PixelSprite {
                id: photo
                x: 9
                y: 9
                pixel: root.pixel
                rows: root.day ? PixelArt.photo(root.day.code, root.day_index) : []
            }
        }

        DotBar {
            id: dot_bar
            anchors.horizontalCenter: parent.horizontalCenter
            low: root.day ? root.day.min : 0
            high: root.day ? root.day.max : 0
            scale_min: root.scale_min
            scale_max: root.scale_max
            dot: root.pixel * 2
        }

        Column {
            id: temp_row
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            PixelTemp {
                anchors.horizontalCenter: parent.horizontalCenter
                value: root.day ? root.day.max : 0
                color: Style.shade_3
                font_size: root.hi_size
            }

            PixelTemp {
                anchors.horizontalCenter: parent.horizontalCenter
                value: root.day ? root.day.min : 0
                color: Style.shade_2
                font_size: root.text_size
            }
        }

        Text {
            id: pop_text
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.day ? root.day.pop + "%" : ""
            color: Style.shade_2
            font.family: Style.font_family
            font.pixelSize: root.text_size
        }
    }
}
