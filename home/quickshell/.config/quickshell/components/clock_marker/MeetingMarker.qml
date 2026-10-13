// home/quickshell/.config/quickshell/components/clock_marker/MeetingMarker.qml
import QtQuick
import "../../theme"

// The bar clock's meeting marker: the countdown before a meeting and the in-meeting mark, drawn by the file Style.bar_meeting_marker names.
Item {
    id: root

    // Minutes to the upcoming meeting; meaningless while in_meeting.
    property int minutes: 0
    property bool in_meeting: false
    // 0..1 through the lead-in window, 1 during a meeting.
    property real progress: 0
    // The clock sits on a strong fill; markers draw in ink.
    property bool on_accent: false
    property color ink: "black"
    property font text_font

    implicitWidth: loader.item ? loader.item.implicitWidth : 0
    implicitHeight: loader.item ? loader.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Component { id: default_marker; DefaultMarker {} }
    Component { id: bracket_tag_marker; BracketTagMarker {} }
    Component { id: glow_flare_marker; GlowFlareMarker {} }
    Component { id: mode_badge_marker; ModeBadgeMarker {} }
    Component { id: bracket_readout_marker; BracketReadoutMarker {} }
    Component { id: hev_readout_marker; HevReadoutMarker {} }
    Component { id: lit_pill_marker; LitPillMarker {} }
    Component { id: pill_badge_marker; PillBadgeMarker {} }
    Component { id: encounter_sprite_marker; EncounterSpriteMarker {} }
    Component { id: pixel_sprite_marker; PixelSpriteMarker {} }
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
        "glow_flare": glow_flare_marker,
        "mode_badge": mode_badge_marker,
        "bracket_readout": bracket_readout_marker,
        "hev_readout": hev_readout_marker,
        "lit_pill": lit_pill_marker,
        "pill_badge": pill_badge_marker,
        "encounter_sprite": encounter_sprite_marker,
        "pixel_sprite": pixel_sprite_marker,
        "pixel_bell": pixel_bell_marker,
        "memory_card": memory_card_marker,
        "atb_gauge": atb_gauge_marker,
        "energy_tanks": energy_tanks_marker,
        "ring_gauge": ring_gauge_marker,
        "lcd_subdial": lcd_subdial_marker,
        "twinkle_star": twinkle_star_marker
    })

    Loader {
        id: loader
        sourceComponent: root.by_token[Style.bar_meeting_marker] || default_marker
    }

    Binding { target: loader.item; property: "minutes"; value: root.minutes }
    Binding { target: loader.item; property: "in_meeting"; value: root.in_meeting }
    Binding { target: loader.item; property: "progress"; value: root.progress }
    Binding { target: loader.item; property: "on_accent"; value: root.on_accent }
    Binding { target: loader.item; property: "ink"; value: root.ink }
    Binding { target: loader.item; property: "text_font"; value: root.text_font }
}
