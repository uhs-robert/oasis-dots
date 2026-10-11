// home/quickshell/.config/quickshell/popups/weather/BattleDayColumn.qml
import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/nes" as Nes
import "../../theme"
import "../../services"
import "NesSprites.js" as NesSprites

// One day as a Dragon Quest enemy: its weather monster, a stack of NES bricks from low to high, an MP-style rain gauge and its name.
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
    readonly property int brick_size: Math.max(6, Math.min(12, Math.floor(root.inner_w / 4)))
    readonly property real pop: root.day ? Math.max(0, Math.min(100, root.day.pop)) : 0

    readonly property var nes_colors: [Style.pal.bg_crust, Style.pal.fg_strong, Style.pal.yellow, Style.pal.bright_yellow, Style.pal.blue, Style.pal.bright_blue, Style.pal.fg_dim, Style.pal.red, Style.pal.fg_muted]

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

        // Whole block slots on the shared scale, so stacks in neighbouring columns line up course for course.
        Item {
            id: range_area
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real text_h: hi_text.height + 2
            readonly property int slots: Math.max(1, Math.floor((height - 2 * text_h) / root.brick_size))
            readonly property int lo_slot: root.day ? Math.round(root.scale_frac(root.day.min) * (slots - 1)) : 0
            readonly property int hi_slot: root.day ? Math.max(lo_slot, Math.round(root.scale_frac(root.day.max) * (slots - 1))) : 0
            readonly property real floor_y: height - text_h

            PixelTemp {
                id: hi_text
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_area.floor_y - (range_area.hi_slot + 1) * root.brick_size - height - 2
                value: root.day ? root.day.max : 0
                color: root.selected ? Style.pal.fg_strong : Style.text_dim
                font_size: Style.fs(-4)
            }

            Canvas {
                id: bricks
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.brick_size
                height: (range_area.hi_slot - range_area.lo_slot + 1) * root.brick_size
                y: range_area.floor_y - (range_area.hi_slot + 1) * root.brick_size
                antialiasing: false
                smooth: false
                opacity: root.selected ? 1 : 0.55

                readonly property color face: Qt.tint(Style.pal.bg_surface, Qt.alpha(Style.pal.bright_yellow, 0.8))
                readonly property color shine: Style.pal.bright_yellow
                readonly property color mortar: Style.pal.bg_crust

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onFaceChanged: requestPaint()

                // Each block is two courses of bricks with staggered joints, like the NES overworld brick.
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const b = root.brick_size, half = Math.floor(b / 2);
                    for (let top = 0; top < height; top += b) {
                        ctx.fillStyle = String(face);
                        ctx.fillRect(0, top, b, b);
                        ctx.fillStyle = String(shine);
                        ctx.fillRect(0, top, b, 1);
                        ctx.fillRect(0, top + half, b, 1);
                        ctx.fillStyle = String(mortar);
                        ctx.fillRect(0, top + half - 1, b, 1);
                        ctx.fillRect(0, top + b - 1, b, 1);
                        ctx.fillRect(half - 1, top, 1, half - 1);
                        ctx.fillRect(b - 1, top + half, 1, half - 1);
                    }
                }
            }

            // The targeted enemy's top block turns into a ? block.
            Nes.QBlock {
                visible: root.selected
                anchors.horizontalCenter: parent.horizontalCenter
                y: bricks.y
                width: root.brick_size
                height: root.brick_size
                mark: root.brick_size >= 10
            }

            PixelTemp {
                anchors.horizontalCenter: parent.horizontalCenter
                y: range_area.floor_y - range_area.lo_slot * root.brick_size + 2
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
