// home/quickshell/.config/quickshell/popups/weather/BattleDayColumn.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "NesSprites.js" as NesSprites

// One day as a Dragon Quest enemy: its weather monster, a tower of slimes from low to high, an MP-style rain gauge and its name.
Item {
    id: root

    property var day: null
    property int day_index: 0
    property string label: ""
    property bool selected: false
    property real col_w: 0
    // The week's coldest low and warmest high, shared by every column so ranges compare across days.
    property real scale_min: 0
    property real scale_max: 1

    // Clears the DqWindow frame DailyView draws behind the column (2px border, 3px gap, 1px inner line).
    readonly property int frame_pad: 8
    readonly property real inner_w: Math.max(16, root.width - 2 * root.frame_pad)
    readonly property int sprite_pixel: Math.max(1, Math.min(3, Math.floor(root.inner_w / 16)))
    readonly property real pop: root.day ? Math.max(0, Math.min(100, root.day.pop)) : 0

    readonly property var nes_colors: [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.yellow, Style.pal.bright_yellow, Style.pal.blue, Style.pal.bright_blue, Style.pal.fg_dim, Style.pal.red, Style.pal.fg_muted]

    // Slimes warm from blue through she-slime orange to red as their slot climbs the week's scale.
    readonly property var slime_tiers: [root.recolor_slime(Style.pal.blue, Style.pal.bright_blue), root.recolor_slime(Style.pal.bright_yellow, Style.pal.yellow), root.recolor_slime(Style.pal.red, Style.pal.bright_yellow)]

    function recolor_slime(body: color, shine: color): var {
        const colors = root.nes_colors.slice();
        colors[4] = body;
        colors[5] = shine;
        return colors;
    }

    function slime_colors(frac: real): var {
        return root.slime_tiers[frac < 0.5 ? 0 : frac < 0.8 ? 1 : 2];
    }

    function scale_frac(v) {
        return Math.max(0, Math.min(1, (v - root.scale_min) / Math.max(0.01, root.scale_max - root.scale_min)));
    }

    // DQ flashes an enemy when the cursor targets it; one burst on selection, never a loop.
    property bool sprite_shown: true

    onSelectedChanged: {
        if (root.selected && Popups.open_name === "weather") flash_anim.restart();
    }

    Connections {
        target: Popups
        function onOpen_nameChanged() {
            if (Popups.open_name !== "weather") {
                flash_anim.stop();
                root.sprite_shown = true;
            }
        }
    }

    SequentialAnimation {
        id: flash_anim
        loops: 3
        PropertyAction { target: root; property: "sprite_shown"; value: false }
        PauseAnimation { duration: 70 }
        PropertyAction { target: root; property: "sprite_shown"; value: true }
        PauseAnimation { duration: 70 }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.frame_pad
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: monster.width
            Layout.preferredHeight: monster.height

            PixelSprite {
                id: monster
                visible: root.sprite_shown
                opacity: root.selected ? 1 : 0.5
                pixel: root.sprite_pixel
                colors: root.nes_colors
                rows: root.day ? NesSprites.monster(root.day.code) : []
            }
        }

        // Whole slime slots on the shared scale, so towers in neighbouring columns line up slime for slime.
        Item {
            id: range_area
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real text_h: hi_text.height + 2
            readonly property real stack_h: height - 2 * text_h
            // Double-size slimes only while they fit the column and still leave enough slots to tell days apart.
            readonly property int slime_pixel: root.inner_w >= 2 * NesSprites.SLIME_SIZE && slots_at(2) >= 6 ? 2 : 1
            readonly property int slime_step: NesSprites.SLIME_STEP * slime_pixel
            readonly property int slots: slots_at(slime_pixel)
            readonly property int lo_slot: root.day ? Math.round(root.scale_frac(root.day.min) * (slots - 1)) : 0
            readonly property int hi_slot: root.day ? Math.max(lo_slot, Math.round(root.scale_frac(root.day.max) * (slots - 1))) : 0
            readonly property real floor_y: height - text_h

            function slots_at(pixel: int): int {
                return Math.max(1, Math.floor((stack_h - NesSprites.SLIME_SIZE * pixel) / (NesSprites.SLIME_STEP * pixel)) + 1);
            }

            function slime_y(slot: int): real {
                return floor_y - slot * slime_step - NesSprites.SLIME_SIZE * slime_pixel;
            }

            PixelTemp {
                id: hi_text
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_area.slime_y(range_area.hi_slot) - height - 2
                value: root.day ? root.day.max : 0
                color: root.selected ? Style.pal.fg_strong : Style.text_dim
                font_size: Style.fs(-4)
            }

            Item {
                anchors.fill: parent
                opacity: root.selected ? 1 : 0.55
                // Faded one by one, overlapping slimes would show through each other.
                layer.enabled: opacity < 1
                layer.smooth: false

                // Later slimes stack above earlier ones, so each base covers the curl of the slime below.
                Repeater {
                    model: root.day ? range_area.hi_slot - range_area.lo_slot + 1 : 0

                    PixelSprite {
                        required property int index
                        readonly property int slot: range_area.lo_slot + index

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: range_area.slime_y(slot)
                        pixel: range_area.slime_pixel
                        colors: root.slime_colors(slot / Math.max(1, range_area.slots - 1))
                        rows: root.selected && slot === range_area.hi_slot ? NesSprites.KING_SLIME : NesSprites.SLIME
                    }
                }
            }

            PixelTemp {
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_area.floor_y - range_area.lo_slot * range_area.slime_step + 2
                value: root.day ? root.day.min : 0
                color: root.selected ? Style.pal.fg_strong : Style.text_dim
                font_size: Style.fs(-4)
            }
        }

        // Rain chance as the enemy's MP: label and number over a blue gauge.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: mp_number.height

            Text {
                anchors.left: parent.left
                anchors.baseline: mp_number.baseline
                text: "MP"
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
            }

            Text {
                id: mp_number
                anchors.right: parent.right
                text: Math.round(root.pop)
                color: root.pop > 0 ? Style.pal.blue : Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 5
            color: Style.pal.bg_crust
            border.width: 1
            border.color: Style.text_muted

            Rectangle {
                x: 1
                y: 1
                width: Math.round((parent.width - 2) * root.pop / 100)
                height: parent.height - 2
                color: Style.pal.blue
            }
        }

        Text {
            id: day_name
            Layout.fillWidth: true
            Layout.topMargin: 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.label
            color: root.selected ? Style.pal.fg_strong : Style.text_dim
            font.family: Style.font_family
            font.pixelSize: Style.fs(-2)

            Text {
                visible: root.selected && Style.caret_phase
                anchors.right: parent.horizontalCenter
                anchors.rightMargin: day_name.contentWidth / 2 + 3
                anchors.verticalCenter: parent.verticalCenter
                text: Style.row_cursor
                color: Style.caret_color
                font.family: Style.font_family
                font.pixelSize: Style.fs(-5)
            }
        }
    }
}
