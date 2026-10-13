// home/quickshell/.config/quickshell/components/clock_marker/MeetingMarker.qml
import QtQuick
import "../../theme"

// The bar clock's meeting marker: the countdown before a meeting and the in-meeting mark, drawn by the file Style.bar_meeting_marker names.
// `minutes` and `progress` describe the upcoming meeting; `in_meeting` is the live one.
MarkerBase {
    id: root

    // A meeting is inside the countdown window. With in_meeting also set (back-to-back meetings) both markers show.
    property bool upcoming: false

    // True is the live marker, false the countdown.
    readonly property var slots: root.in_meeting && root.upcoming ? [true, false] : [root.in_meeting]

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Component { id: default_marker; DefaultMarker {} }
    Component { id: bracket_tag_marker; BracketTagMarker {} }
    Component { id: vt100_led_marker; Vt100LedMarker {} }
    Component { id: mode_badge_marker; ModeBadgeMarker {} }
    Component { id: bracket_readout_marker; BracketReadoutMarker {} }
    Component { id: hev_readout_marker; HevReadoutMarker {} }
    Component { id: lit_pill_marker; LitPillMarker {} }
    Component { id: pill_badge_marker; PillBadgeMarker {} }
    Component { id: encounter_sprite_marker; EncounterSpriteMarker {} }
    Component { id: reserve_box_marker; ReserveBoxMarker {} }
    Component { id: pixel_bell_marker; PixelBellMarker {} }
    Component { id: memory_card_marker; MemoryCardMarker {} }
    Component { id: atb_gauge_marker; AtbGaugeMarker {} }
    Component { id: energy_tanks_marker; EnergyTanksMarker {} }
    Component { id: ring_gauge_marker; RingGaugeMarker {} }
    Component { id: lcd_subdial_marker; LcdSubdialMarker {} }
    Component { id: twinkle_star_marker; TwinkleStarMarker {} }

    readonly property var by_token: ({
        "": default_marker,
        "bracket_tag": bracket_tag_marker,
        "vt100_led": vt100_led_marker,
        "mode_badge": mode_badge_marker,
        "bracket_readout": bracket_readout_marker,
        "hev_readout": hev_readout_marker,
        "lit_pill": lit_pill_marker,
        "pill_badge": pill_badge_marker,
        "encounter_sprite": encounter_sprite_marker,
        "reserve_box": reserve_box_marker,
        "pixel_bell": pixel_bell_marker,
        "memory_card": memory_card_marker,
        "atb_gauge": atb_gauge_marker,
        "energy_tanks": energy_tanks_marker,
        "ring_gauge": ring_gauge_marker,
        "lcd_subdial": lcd_subdial_marker,
        "twinkle_star": twinkle_star_marker
    })

    Row {
        id: row
        spacing: 6

        Repeater {
            model: root.slots

            Loader {
                id: loader
                required property bool modelData
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: root.by_token[Style.bar_meeting_marker] || default_marker

                Binding { target: loader.item; property: "minutes"; value: root.minutes }
                Binding { target: loader.item; property: "in_meeting"; value: loader.modelData }
                Binding { target: loader.item; property: "progress"; value: loader.modelData ? 1 : root.progress }
                Binding { target: loader.item; property: "on_accent"; value: root.on_accent }
                Binding { target: loader.item; property: "ink"; value: root.ink }
                Binding { target: loader.item; property: "text_font"; value: root.text_font }
            }
        }
    }
}
