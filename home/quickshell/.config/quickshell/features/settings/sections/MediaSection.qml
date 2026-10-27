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
        inline: "Artist - Title", stacked: "Title over artist",
        inset: "Inset", border: "Border", raised: "Raised"
    })

    // Labels for a value whose shared name is wrong for one setting ("none" is "Nothing" for the scroll action only).
    readonly property var key_names: ({ container_style: { none: "No container" } })

    function on_off(key) {
        return { values: () => ["on", "off"], text: v => v, value: () => MediaSettings[key] ? "on" : "off", set: v => MediaSettings.set(key, v === "on") };
    }

    function choice(key) {
        return { values: () => MediaSettings.choices[key], text: v => (root.key_names[key] && root.key_names[key][v]) || root.names[v] || String(v), value: () => MediaSettings[key], set: v => MediaSettings.set(key, v) };
    }

    function count(key, first, last, step) {
        const list = [];
        for (let n = first; n <= last; n += step) list.push(n);
        return { values: () => list, text: v => String(v), value: () => MediaSettings[key], set: v => MediaSettings.set(key, v) };
    }

    footer_hint: "j/k move · " + root.layout_hint + "H/L change · Enter list · c cava line · h/Esc sections · q close"
    rows: [
        { heading: "Visualizer" },
        Object.assign({ label: "Right side", desc: "What the media module shows on its right: the audio visualizer, or the track position." }, root.choice("right_side_mode")),
        Object.assign({ label: "On battery", desc: "The visualizer costs power, so on battery the right side shows the track position or is hidden." }, root.choice("battery_fallback")),
        Object.assign({ label: "Cava line", desc: "Draw the audio visualizer as a smooth line. Off draws separate bars.", keys: "H/L or c toggle · Enter list" }, root.on_off("cava_line")),
        Object.assign({ label: "Scroll", desc: "What the mouse wheel does over the media module. Volume: scroll sets the volume. Whatever you pick, scrolling over the cava or position area seeks." }, root.choice("scroll_action")),
        { heading: "Layout" },
        Object.assign({ label: "Island styles", desc: "Where media shows in island bar styles. Strip and frame styles always show the module." }, root.choice("island_mode")),
        Object.assign({ label: "Container", desc: "How the media module sits in the bar: pressed in, outlined, lifted, or none to draw it straight on the bar." }, root.choice("container_style")),
        Object.assign({ label: "Show album art", desc: "Show the album art thumbnail in the media module. Off leaves the play/pause button first." }, root.on_off("show_art")),
        Object.assign({ label: "Show play/pause", desc: "Show the play/pause button in the media module. Off drops it and its gap; middle-click still toggles playback." }, root.on_off("show_button")),
        Object.assign({ label: "Show title", desc: "Show the track title in the media module." }, root.on_off("show_title")),
        Object.assign({ label: "Show artist", desc: "Show the artist in the media module." }, root.on_off("show_artist")),
        { heading: "Text" },
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

    pinned: MediaPreview {
        Layout.fillWidth: true
        popup: root.popup
        active: root.popup ? root.popup.is_open : false
    }
}
