// home/quickshell/.config/quickshell/settings/sections/WallpaperSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property int top_count: 5
    readonly property var monitors: Displays.monitors.filter(m => !m.disabled)
    readonly property var current_monitor: root.cursor >= root.top_count ? root.monitors[root.cursor - root.top_count] || null : null
    // Set while the collection is being listed, so the image list opens for the monitor that asked.
    property var awaiting: null
    readonly property string hint: WallpaperSettings.notice !== "" ? WallpaperSettings.notice : WallpaperSettings.alive ? "" : "The rotator is not running; changes apply when it starts."

    footer_hint: root.current_monitor ? "j/k move · h/l change · Enter image · p pin current · Esc sections · q close" : "j/k move · h/l change · Enter list · Esc sections · q close"

    function toggle_row(label, key) {
        return {
            label: label,
            values: () => ["on", "off"],
            text: v => v,
            value: () => WallpaperSettings.effective(key) ? "on" : "off",
            set: v => WallpaperSettings.set_value(key, v === "on")
        };
    }

    function monitor_row(m) {
        return {
            label: m.model !== "" ? m.name + " · " + m.model : m.name,
            values: () => ["auto", "pinned"],
            text: v => v === "pinned" ? "Pinned" : "Automatic",
            value: () => m.key in WallpaperSettings.pins ? "pinned" : "auto",
            set: v => v === "pinned" ? root.pin_current(m) : WallpaperSettings.clear_pin(m.key),
            pick: false,
            activate: () => root.choose_image(m)
        };
    }

    rows: [
        root.toggle_row("Automatic rotation", "rotation"),
        {
            label: "Interval",
            values: () => {
                const now = WallpaperSettings.effective("interval_minutes");
                const all = WallpaperSettings.interval_choices.indexOf(now) >= 0 ? WallpaperSettings.interval_choices : WallpaperSettings.interval_choices.concat([now]);
                return all.slice().sort((a, b) => a - b);
            },
            text: v => v + " min",
            value: () => WallpaperSettings.effective("interval_minutes"),
            set: v => WallpaperSettings.set_value("interval_minutes", v)
        },
        root.toggle_row("Time of day", "time_of_day_enabled"),
        root.toggle_row("Seasons", "seasons_enabled"),
        root.toggle_row("Weather", "weather_enabled")
    ].concat(root.monitors.map(m => root.monitor_row(m)))

    function pin_current(m) {
        if (m.key in WallpaperSettings.pins) return;
        WallpaperSettings.pin_current(m);
    }

    function choose_image(m) {
        root.awaiting = m;
        WallpaperSettings.list_images();
    }

    function open_images(m) {
        const images = WallpaperSettings.images;
        if (images.length === 0) {
            WallpaperSettings.say("No images found in " + WallpaperSettings.collection);
            return;
        }
        root.open_list("Pin image on " + m.name, images, images.map(p => WallpaperSettings.base_name(p)), WallpaperSettings.pins[m.key], p => WallpaperSettings.set_pin(m.key, p), images.map(p => WallpaperSettings.url_of(p)));
    }

    onExtra_key: event => {
        if (event.key !== Qt.Key_P || !root.current_monitor) return;
        root.pin_current(root.current_monitor);
        event.accepted = true;
    }

    Connections {
        target: WallpaperSettings
        function onImages_ready() {
            const m = root.awaiting;
            root.awaiting = null;
            if (m && root.live) root.open_images(m);
        }
    }

    Component.onCompleted: {
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

        RowLayout {
            visible: !root.picking && !!root.current_monitor
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: {
                    const m = root.current_monitor;
                    if (!m) return [];
                    const entry = WallpaperSettings.live[m.name];
                    const out = [{ title: "Showing", path: entry && typeof entry.path === "string" ? entry.path : "" }];
                    if (m.key in WallpaperSettings.pins) out.push({ title: "Pinned", path: WallpaperSettings.pins[m.key] });
                    return out;
                }

                ColumnLayout {
                    id: card
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(width * 9 / 16)
                        color: Theme.bg_shadow
                        border.width: 1
                        border.color: Qt.alpha(root.st.text_muted, 0.4)
                        radius: Style.px(4)
                        clip: true

                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: card.modelData.path !== "" ? WallpaperSettings.url_of(card.modelData.path) : ""
                            sourceSize: Qt.size(480, 270)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: card.modelData.title + (card.modelData.path !== "" ? " · " + WallpaperSettings.base_name(card.modelData.path) : "")
                        elide: Text.ElideMiddle
                        color: root.st.text_dim
                        font.family: root.st.font_family
                        font.pixelSize: root.st.fs(-3)
                    }
                }
            }
        }

        Text {
            visible: !root.picking
            Layout.fillWidth: true
            text: "Collection: " + WallpaperSettings.collection + ". Saved to " + Paths.hypr_state_dir + "/wallpaper.json"
            wrapMode: Text.WrapAnywhere
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }
}
