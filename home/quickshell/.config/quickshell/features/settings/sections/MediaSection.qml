import QtQuick
import QtQuick.Layouts
import qs.features.settings
import qs.features.media

RowsSection {
    id: root

    readonly property var names: ({
        cava: "Cava", position: "Track position", hide: "Hide",
        volume_seek: "Volume and seek", skip: "Next and previous", none: "Nothing",
        cava_under_island: "Cava under the clock island", module_only: "Media module only", split: "Both",
        inline: "Artist - Title", stacked: "Title over artist"
    })

    function on_off(key) {
        return { values: () => ["on", "off"], text: v => v, value: () => MediaSettings[key] ? "on" : "off", set: v => MediaSettings.set(key, v === "on") };
    }

    function choice(key) {
        return { values: () => MediaSettings.choices[key], text: v => root.names[v] || String(v), value: () => MediaSettings[key], set: v => MediaSettings.set(key, v) };
    }

    function count(key, first, last, step) {
        const list = [];
        for (let n = first; n <= last; n += step) list.push(n);
        return { values: () => list, text: v => String(v), value: () => MediaSettings[key], set: v => MediaSettings.set(key, v) };
    }

    footer_hint: "j/k move · H/L change · Enter list · c cava line · h/Esc sections · q close"
    rows: [
        Object.assign({ label: "Right side", desc: "What the media module shows on its right: the audio visualizer, or the track position." }, root.choice("right_side_mode")),
        Object.assign({ label: "On battery", desc: "The visualizer costs power, so on battery the right side shows the track position or is hidden." }, root.choice("battery_fallback")),
        Object.assign({ label: "Scroll", desc: "What the mouse wheel does over the media module. Volume and seek: scroll sets the volume, Shift+scroll seeks." }, root.choice("scroll_action")),
        Object.assign({ label: "Cava line", desc: "Draw the audio visualizer as a smooth line. Off draws separate bars.", keys: "H/L or c toggle · Enter list" }, root.on_off("cava_line")),
        Object.assign({ label: "Island styles", desc: "Where media shows in island bar styles. Strip and frame styles always show the module." }, root.choice("island_mode")),
        Object.assign({ label: "Show title", desc: "Show the track title in the media module." }, root.on_off("show_title")),
        Object.assign({ label: "Show artist", desc: "Show the artist in the media module." }, root.on_off("show_artist")),
        Object.assign({ label: "Text layout", desc: "Artist and title on one line, or the title with a smaller artist line under it." }, root.choice("text_layout")),
        Object.assign({ label: "Text width", desc: "The most characters of title and artist shown before an ellipsis." }, root.count("max_chars", 8, 60, 4)),
        Object.assign({ label: "Scroll long text", desc: "Scroll text that does not fit instead of cutting it with an ellipsis." }, root.on_off("text_scroll")),
        Object.assign({ label: "Scroll speed", desc: "How fast long text scrolls, in pixels per second." }, root.count("text_scroll_speed", 10, 120, 10))
    ]

    onExtra_key: event => {
        if (event.key !== Qt.Key_C) return;
        MediaSettings.set("cava_line", !MediaSettings.cava_line);
        event.accepted = true;
    }
}
