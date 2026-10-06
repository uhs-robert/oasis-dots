// home/quickshell/.config/quickshell/settings/sections/WallpaperSection.qml
import QtQuick
import Quickshell
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

    section_keys: "o open folder"
    footer_hint: root.current_monitor ? "j/k move · h/l change · Enter image · p pin current · r rotate " + root.current_monitor.name + " · o open folder · Esc sections · q close" : "j/k move · h/l change · Enter list · r rotate all · o open folder · Esc sections · q close"

    function toggle_row(label, key, desc) {
        return {
            label: label,
            desc: desc,
            keys: "h/l toggle · r rotate all",
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
            keys: "h/l mode · Enter choose image · p pin current · r rotate " + m.name,
            values: () => ["auto", "pinned"],
            text: v => v === "pinned" ? "Pinned" : "Automatic",
            value: () => m.key in WallpaperSettings.pins ? "pinned" : "auto",
            set: v => v === "pinned" ? root.pin_current(m) : WallpaperSettings.clear_pin(m.key),
            pick: false,
            activate: () => root.choose_image(m)
        };
    }

    rows: [
        root.toggle_row("Automatic rotation", "rotation", "Change wallpapers on a timer. Off keeps each image until you rotate."),
        {
            label: "Interval",
            desc: "Minutes between rotations. A new part of the day also rotates.",
            keys: "h/l change · Enter list · r rotate all",
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
        root.toggle_row("Weather", "weather_enabled", "Mix in the Rain, Snow or Cloudy folder while that weather is current.")
    ].concat(root.monitors.map(m => root.monitor_row(m)))

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
        if (event.key === Qt.Key_P && root.current_monitor) root.pin_current(root.current_monitor);
        else if (event.key === Qt.Key_R) root.rotate(root.current_monitor);
        else if (event.key === Qt.Key_O) WallpaperSettings.open_collection();
        else return;
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
                    const pinned = m.key in WallpaperSettings.pins;
                    return [
                        { title: "Showing", path: entry && typeof entry.path === "string" ? entry.path : "" },
                        { title: pinned ? "Pinned" : "Not pinned", path: pinned ? WallpaperSettings.pins[m.key] : "" }
                    ];
                }

                ColumnLayout {
                    id: card
                    required property var modelData

                    // Equal halves: the shared preferred width splits the row evenly.
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
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
                        elide: Text.ElideRight
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
            text: "Collection  " + WallpaperSettings.collection.replace(Quickshell.env("HOME"), "~")
            elide: Text.ElideMiddle
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }
}
