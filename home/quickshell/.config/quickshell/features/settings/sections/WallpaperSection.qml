import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.theme
import qs.features.display
import qs.features.settings
import qs.features.popups
import "../WallpaperStrip.js" as Strip

RowsSection {
    id: root

    readonly property int top_count: 6
    readonly property var monitors: Displays.monitors.filter(m => !m.disabled)
    readonly property var current_monitor: root.cursor >= root.top_count ? root.monitors[root.cursor - root.top_count] || null : null
    property bool editing: false
    // Set while the collection is being listed for the searchable pin list, so it opens for the monitor that asked.
    property var awaiting: null
    // True while the keys move the filmstrip; Enter on a monitor row goes in and Esc comes back to the rows.
    property bool in_strip: false
    property int strip_cursor: 0
    property int strip_target: 0
    // A lone g waits here for the second one of gg.
    property bool g_pending: false
    // The folder the last listing was made for, to list again when the folder changes during a run.
    property string listed_for: ""
    readonly property var images: WallpaperSettings.images
    // Outside the filmstrip the hero shows what the selected monitor shows now.
    readonly property int shown_target: root.in_strip ? root.strip_target : Math.max(0, root.monitors.indexOf(root.current_monitor))
    readonly property string shown_path: {
        const m = root.monitors[root.shown_target];
        if (!m) return "";
        if (m.key in WallpaperSettings.pins) return WallpaperSettings.pins[m.key];
        const entry = WallpaperSettings.live[m.name];
        return entry && typeof entry.path === "string" ? entry.path : "";
    }
    // The hero previews what the monitor really shows, even when that file is not in the listed collection; the index only seeds the filmstrip.
    readonly property string hero_path: root.in_strip ? root.images[root.strip_cursor] || "" : root.shown_path
    readonly property int shown_cursor: root.in_strip ? root.strip_cursor : Strip.index_of(root.images, root.shown_path, Math.floor(root.images.length / 2))
    readonly property var strip_monitor: root.monitors[root.strip_target] || null
    readonly property string home_dir: Quickshell.env("HOME")
    readonly property string hint: WallpaperSettings.notice !== "" ? WallpaperSettings.notice : WallpaperSettings.alive ? "" : "The rotator is not running; changes apply when it starts."

    section_keys: "o open folder"
    footer_hint: root.editing ? "Enter save · empty resets · Ctrl+u clear · Esc cancel" : root.in_strip ? "h/l move · gg/G first/last · j/k monitor · Enter pin on " + (root.strip_monitor ? root.strip_monitor.name : "") + " · p unpin · / search · Esc back to rows" : root.current_monitor ? "j/k move · H/L change · Enter images · / search images · p pin/unpin · r rotate " + root.current_monitor.name + " · o open folder · h/Esc sections · q close" : "j/k move · H/L change · Enter list · r rotate all · o open folder · h/Esc sections · q close"

    // On the strip the help card lists the strip's keys instead of the monitor row's.
    description: root.in_strip ? "Pick an image for " + (root.strip_monitor ? root.strip_monitor.name : "a monitor") + " from the collection." : root.described_row && root.described_row.desc ? root.described_row.desc : ""
    description_keys: root.in_strip ? "h/l move · gg/G first/last · j/k or Tab monitor · Enter pin · p unpin · / search list · Esc back" : root.keys_of(root.described_row)

    function toggle_row(label, key, desc) {
        return {
            label: label,
            desc: desc,
            keys: "H/L toggle · r rotate all",
            values: () => ["on", "off"],
            text: v => v,
            value: () => WallpaperSettings.effective(key) ? "on" : "off",
            set: v => WallpaperSettings.set_value(key, v === "on")
        };
    }

    function monitor_row(m) {
        return {
            label: m.model !== "" ? m.name + " · " + m.model : m.name,
            desc: "Automatic follows the rotation. Pinned keeps one image on this screen.",
            keys: "H/L mode · Enter browse images · / search images · p pin/unpin · r rotate " + m.name,
            values: () => ["auto", "pinned"],
            text: v => v === "pinned" ? "Pinned" : "Automatic",
            value: () => m.key in WallpaperSettings.pins ? "pinned" : "auto",
            set: v => v === "pinned" ? root.pin_current(m) : WallpaperSettings.clear_pin(m.key),
            pick: false,
            activate: () => root.enter_strip(m)
        };
    }

    rows: [
        root.toggle_row("Automatic rotation", "rotation", "Change wallpapers on a timer. Off keeps each image until you rotate."),
        {
            label: "Interval",
            desc: "Minutes between rotations. A new part of the day also rotates.",
            keys: "H/L change · Enter list · r rotate all",
            values: () => {
                const now = WallpaperSettings.effective("interval_minutes");
                const all = WallpaperSettings.interval_choices.indexOf(now) >= 0 ? WallpaperSettings.interval_choices : WallpaperSettings.interval_choices.concat([now]);
                return all.slice().sort((a, b) => a - b);
            },
            text: v => v + " min",
            value: () => WallpaperSettings.effective("interval_minutes"),
            set: v => WallpaperSettings.set_value("interval_minutes", v)
        },
        root.toggle_row("Time of day", "time_of_day_enabled", "Use the Dawn, Day, Evening or Night folder. Off uses the whole collection."),
        root.toggle_row("Seasons", "seasons_enabled", "Add the current season's folder to Any. Off uses only Any."),
        root.toggle_row("Weather", "weather_enabled", "Mix in the Rain, Snow or Cloudy folder while that weather is current."),
        {
            label: "Collection",
            desc: "Folder the wallpapers come from. Enter types a new path; empty goes back to the default.",
            keys: "Enter edit · empty resets",
            values: () => [],
            text: v => root.tilde(v),
            value: () => WallpaperSettings.collection,
            set: v => {},
            cycle: false,
            activate: () => root.start_edit()
        }
    ].concat(root.monitors.map(m => root.monitor_row(m)))

    function tilde(path) {
        return path === root.home_dir || path.startsWith(root.home_dir + "/") ? "~" + path.substring(root.home_dir.length) : path;
    }

    function start_edit() {
        root.editing = true;
        input.text = root.tilde(WallpaperSettings.collection);
        input.forceActiveFocus();
        input.selectAll();
    }

    function end_edit() {
        // The section is a focus scope: unless the field gives up its scoped focus, forceActiveFocus hands it straight back to the hidden field and keys go nowhere.
        input.focus = false;
        root.editing = false;
        root.forceActiveFocus();
    }

    function commit_edit() {
        const text = input.text.trim();
        if (text === "") {
            WallpaperSettings.clear_value("wallpaper_dir");
            WallpaperSettings.say("Collection reset to the default");
        } else {
            WallpaperSettings.set_collection(text);
        }
        root.end_edit();
    }

    function toggle_pin(m) {
        if (m.key in WallpaperSettings.pins) WallpaperSettings.clear_pin(m.key);
        else root.pin_current(m);
    }

    function pin_current(m) {
        if (m.key in WallpaperSettings.pins) return;
        WallpaperSettings.pin_current(m);
    }

    function rotate(m) {
        if (m && m.key in WallpaperSettings.pins) {
            WallpaperSettings.say(m.name + " is pinned; set it to Automatic to rotate it");
            return;
        }
        WallpaperSettings.rotate(m ? m.name : "");
        WallpaperSettings.say(m ? "New image for " + m.name : "New images for the automatic monitors");
    }

    // The listing runs one at a time: a folder change during a run is picked up when that run ends.
    function refresh_images() {
        if (WallpaperSettings.listing) return;
        root.listed_for = WallpaperSettings.collection;
        WallpaperSettings.list_images();
    }

    function choose_image(m) {
        root.awaiting = m;
        root.refresh_images();
    }

    function open_images(m) {
        const images = WallpaperSettings.images;
        if (images.length === 0) {
            WallpaperSettings.say("No images found in " + WallpaperSettings.collection);
            return;
        }
        root.open_list("Pin image on " + m.name, images, images.map(p => WallpaperSettings.base_name(p)), WallpaperSettings.pins[m.key], p => WallpaperSettings.set_pin(m.key, p), images.map(p => WallpaperSettings.url_of(p)), true);
    }

    function enter_strip(m) {
        if (root.images.length === 0) {
            WallpaperSettings.say("No images found in " + WallpaperSettings.collection);
            return;
        }
        root.strip_target = Math.max(0, root.monitors.indexOf(m));
        root.strip_cursor = root.shown_cursor;
        root.in_strip = true;
    }

    // The strip takes Esc, h and Tab before the popup would use them to go back to the sidebar.
    function strip_key(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (event.key !== Qt.Key_G || (event.modifiers & Qt.ShiftModifier)) root.g_pending = false;
        const n = root.images.length;
        const count = root.monitors.length;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const m = root.strip_monitor;
        if (event.key === Qt.Key_Escape) root.in_strip = false;
        else if (event.key === Qt.Key_Slash) {
            if (m) root.choose_image(m);
        }
        else if (event.key === Qt.Key_H) root.strip_cursor = Strip.move(root.strip_cursor, "prev", n);
        else if (event.key === Qt.Key_L) root.strip_cursor = Strip.move(root.strip_cursor, "next", n);
        else if (event.key === Qt.Key_J || event.key === Qt.Key_Tab) root.strip_target = Strip.step_monitor(root.strip_target, 1, count);
        else if (event.key === Qt.Key_K || event.key === Qt.Key_Backtab) root.strip_target = Strip.step_monitor(root.strip_target, -1, count);
        else if (event.key === Qt.Key_G && shift) root.strip_cursor = Strip.move(root.strip_cursor, "last", n);
        else if (event.key === Qt.Key_G) {
            const g = Strip.gg(root.g_pending, true);
            if (g.first) root.strip_cursor = Strip.move(root.strip_cursor, "first", n);
            root.g_pending = g.pending;
            event.accepted = true;
            return;
        }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (m && n > 0) WallpaperSettings.set_pin(m.key, root.images[root.strip_cursor]);
        }
        else if (event.key === Qt.Key_P) {
            if (m) WallpaperSettings.clear_pin(m.key);
        }
        else return;
        event.accepted = true;
    }

    onIn_stripChanged: root.g_pending = false

    onFirst_key: event => {
        if (root.editing) return;
        if (root.in_strip) {
            root.strip_key(event);
            return;
        }
        if (event.key === Qt.Key_Slash && root.current_monitor) {
            root.choose_image(root.current_monitor);
            event.accepted = true;
            return;
        }
        const open = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_L || event.key === Qt.Key_Space;
        if (root.cursor !== root.top_count - 1 || !open) return;
        root.start_edit();
        event.accepted = true;
    }

    onExtra_key: event => {
        if (event.key === Qt.Key_P && root.current_monitor) root.toggle_pin(root.current_monitor);
        else if (event.key === Qt.Key_R) root.rotate(root.current_monitor);
        else if (event.key === Qt.Key_O) {
            Popups.after_close(() => DefaultAppsSettings.open_folder(WallpaperSettings.collection));
        }
        else return;
        event.accepted = true;
    }

    Connections {
        target: WallpaperSettings
        // A new folder, or the first status read, changes what the filmstrip lists.
        function onCollectionChanged() {
            root.refresh_images();
        }

        function onImages_ready() {
            root.strip_cursor = Strip.move(root.strip_cursor, "stay", root.images.length);
            if (root.images.length === 0) root.in_strip = false;
            // These results are for an older folder: list the current one and keep any pending search waiting for it.
            if (root.listed_for !== WallpaperSettings.collection) {
                root.refresh_images();
                return;
            }
            const asked = root.awaiting;
            root.awaiting = null;
            if (asked && root.live) root.open_images(asked);
        }
    }

    Component.onCompleted: {
        root.refresh_images();
        Displays.refresh();
        WallpaperSettings.watching = true;
    }
    Component.onDestruction: WallpaperSettings.watching = false

    Text {
        visible: root.hint !== ""
        Layout.fillWidth: true
        text: root.hint
        wrapMode: Text.WordWrap
        color: root.st.text_accent
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-2)
    }

    footer: ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Rectangle {
            id: edit_box
            visible: root.editing
            Layout.fillWidth: true
            Layout.preferredHeight: Style.px(28)
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: root.st.text_accent

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                maximumLength: 256
                clip: true
                color: root.st.text_fg
                selectionColor: root.st.selection_bg
                selectedTextColor: root.st.selection_inverse ? root.st.selection_fg : root.st.text_fg
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
                onActiveFocusChanged: if (!input.activeFocus && root.editing) root.editing = false

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) root.end_edit();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit_edit();
                    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) input.text = "";
                    else return;
                    event.accepted = true;
                }
            }
        }

        WallpaperHero {
            visible: !root.picking && root.images.length > 0
            Layout.fillWidth: true
            st: root.st
            images: root.images
            monitors: root.monitors
            pins: WallpaperSettings.pins
            path: root.hero_path
            cursor: root.shown_cursor
            target: root.shown_target
            active: root.in_strip
        }
    }
}
