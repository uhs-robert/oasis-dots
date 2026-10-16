import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../../services"
import "NesSprites.js" as NesSprites
import "../../components/nes/Slimes.js" as Slimes

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
    // 0 temp and rain; 1 wind, 2 UV, 3 sunshine show one stat as a vertical gauge. wind_max is the week's strongest gust.
    property int sub: 0
    property real wind_max: 1

    // Clears the DqWindow frame DailyView draws behind the column (2px border, 3px gap, 1px inner line).
    readonly property int frame_pad: 8
    readonly property real inner_w: Math.max(16, root.width - 2 * root.frame_pad)
    readonly property int sprite_pixel: Math.max(1, Math.min(3, Math.floor(root.inner_w / 16)))
    readonly property real pop: root.day ? Math.max(0, Math.min(100, root.day.pop)) : 0

    readonly property var nes_colors: palette.colors

    BattlePalette {
        id: palette
    }

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

    readonly property var uv_short: ({ "Moderate": "MOD", "Very High": "V.HIGH", "Extreme": "EXT" })

    // The gauge's stat: how full it is, the tick standing out of it (-1 for none), its colour and the figure above it.
    readonly property var stat: {
        const d = root.day;
        if (!d) return { fill: 0, tick: -1, color: Style.pal.fg_strong, value: "", foot: "" };
        if (root.sub === 1) return { fill: d.wind_speed_max / root.wind_max, tick: d.wind_gusts_max / root.wind_max, color: Style.pal.cyan, value: String(Math.round(d.wind_speed_max)), foot: "G" + Math.round(d.wind_gusts_max) };
        if (root.sub === 2) {
            const band = WeatherState.uv_band(d.uv_max).label;
            return { fill: d.uv_max / 12, tick: -1, color: WeatherState.uv_color(d.uv_max), value: d.uv_max.toFixed(1), foot: (root.uv_short[band] || band).toUpperCase() };
        }
        return { fill: d.sunshine_hours / 14, tick: -1, color: Style.pal.yellow, value: d.sunshine_hours.toFixed(1), foot: "HRS" };
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
            visible: root.sub === 0
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real text_h: hi_text.height + 2
            readonly property real stack_h: height - 2 * text_h
            // Double-size slimes only while they fit the column and still leave enough slots to tell days apart.
            readonly property int slime_pixel: root.inner_w >= 2 * Slimes.SIZE && slots_at(2) >= 6 ? 2 : 1
            readonly property int slime_step: NesSprites.SLIME_STEP * slime_pixel
            readonly property int slots: slots_at(slime_pixel)
            readonly property int lo_slot: root.day ? Math.round(root.scale_frac(root.day.min) * (slots - 1)) : 0
            readonly property int hi_slot: root.day ? Math.max(lo_slot, Math.round(root.scale_frac(root.day.max) * (slots - 1))) : 0
            readonly property real floor_y: height - text_h

            function slots_at(pixel: int): int {
                return Math.max(1, Math.floor((stack_h - Slimes.SIZE * pixel) / (NesSprites.SLIME_STEP * pixel)) + 1);
            }

            function slime_y(slot: int): real {
                return floor_y - slot * slime_step - Slimes.SIZE * slime_pixel;
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
                        rows: root.selected && slot === range_area.hi_slot ? Slimes.KING_SLIME : Slimes.SLIME
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

        // Wind, UV or sunshine as the enemy's HP: the figure over a vertical gauge, with a footnote line.
        Item {
            id: stat_area
            visible: root.sub > 0
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real fill: Math.max(0, Math.min(1, root.stat.fill))
            readonly property real gauge_h: stat_text.height > 0 ? height - stat_text.height - foot_text.height - 12 : 0
            readonly property int bar_w: 14

            Row {
                id: stat_text
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                Text {
                    visible: root.sub === 1 && !!root.day
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▲"
                    rotation: root.day ? root.day.wind_dir : 0
                    color: Style.pal.cyan
                    font.pixelSize: Style.fs(-4)
                }

                Text {
                    text: root.stat.value
                    color: root.selected ? root.stat.color : Qt.alpha(root.stat.color, 0.6)
                    font.family: Style.font_family
                    font.pixelSize: Style.fs(-3)
                }
            }

            Rectangle {
                id: stat_gauge
                anchors.horizontalCenter: parent.horizontalCenter
                y: stat_text.height + 4
                width: stat_area.bar_w
                height: Math.max(8, stat_area.gauge_h)
                color: Style.pal.bg_crust
                border.width: 1
                border.color: root.selected ? Style.pal.fg_strong : Style.text_muted

                Rectangle {
                    x: 2
                    width: parent.width - 4
                    height: Math.round((parent.height - 4) * stat_area.fill)
                    y: parent.height - 2 - height
                    color: root.stat.color
                    opacity: root.selected ? 1 : 0.55
                }

                Rectangle {
                    visible: root.stat.tick >= 0
                    x: -2
                    width: parent.width + 4
                    height: 2
                    y: parent.height - 2 - Math.round((parent.height - 4) * Math.min(1, root.stat.tick)) - 1
                    color: Style.pal.fg_strong
                }
            }

            Text {
                id: foot_text
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: Math.min(implicitWidth, parent.width)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.stat.foot
                color: Style.text_muted
                font.family: Style.font_family
                font.pixelSize: Style.fs(-6)
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
