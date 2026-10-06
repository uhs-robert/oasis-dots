// home/quickshell/.config/quickshell/settings/sections/WallpaperSection.qml
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property int top_count: 6
    readonly property var monitors: Displays.monitors.filter(m => !m.disabled)
    readonly property var current_monitor: root.cursor >= root.top_count ? root.monitors[root.cursor - root.top_count] || null : null
    // Set while the collection is being listed, so the image list opens for the monitor that asked.
    property var awaiting: null
    property bool editing: false
    readonly property string home_dir: Quickshell.env("HOME")
    readonly property string hint: WallpaperSettings.notice !== "" ? WallpaperSettings.notice : WallpaperSettings.alive ? "" : "The rotator is not running; changes apply when it starts."

    section_keys: "o open folder"
    footer_hint: root.editing ? "Enter save · empty resets · Ctrl+u clear · Esc cancel" : root.current_monitor ? "j/k move · H/L change · Enter image · p pin current · r rotate " + root.current_monitor.name + " · o open folder · h/Esc sections · q close" : "j/k move · H/L change · Enter list · r rotate all · o open folder · h/Esc sections · q close"

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
            keys: "H/L mode · Enter choose image · p pin current · r rotate " + m.name,
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

    onFirst_key: event => {
        if (root.editing) return;
        const open = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_L || event.key === Qt.Key_Space;
        if (root.cursor !== root.top_count - 1 || !open) return;
        root.start_edit();
        event.accepted = true;
    }

    onExtra_key: event => {
        if (event.key === Qt.Key_P && root.current_monitor) root.pin_current(root.current_monitor);
        else if (event.key === Qt.Key_R) root.rotate(root.current_monitor);
        else if (event.key === Qt.Key_O) {
            // Closing first hands keyboard focus back, so the file manager window takes it when it maps.
            Popups.close();
            DefaultApps.open_folder(WallpaperSettings.collection);
        }
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
                selectionColor: root.st.text_accent
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

        // One preview of the selected monitor's image, marked when it is the pin. Its height is capped by the pane's free space, but the cap stays out of the implicit height so the pane cannot grow by it.
        Item {
            id: preview
            readonly property var monitor: root.current_monitor
            readonly property bool pinned: !!preview.monitor && preview.monitor.key in WallpaperSettings.pins
            readonly property var entry: preview.monitor ? WallpaperSettings.live[preview.monitor.name] : undefined
            readonly property string path: preview.pinned ? WallpaperSettings.pins[preview.monitor.key] : preview.entry && typeof preview.entry.path === "string" ? preview.entry.path : ""
            readonly property real wanted: Math.round(width * 9 / 16)
            readonly property real free: root.height - root.footer_top - (root.editing ? edit_box.height + 4 : 0) - root.description_height - preview_label.implicitHeight - 6

            visible: !root.picking && !!preview.monitor
            Layout.fillWidth: true
            Layout.preferredHeight: preview.wanted + preview_label.implicitHeight + 2

            Rectangle {
                id: frame
                width: parent.width
                height: Math.max(0, Math.min(preview.wanted, preview.free))
                color: Theme.bg_shadow
                border.width: 1
                border.color: preview.pinned ? root.st.text_accent : Qt.alpha(root.st.text_muted, 0.4)
                radius: Style.px(4)
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    source: preview.path !== "" ? WallpaperSettings.url_of(preview.path) : ""
                    sourceSize: Qt.size(960, 540)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }

                Rectangle {
                    visible: preview.pinned
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 6
                    width: badge_row.implicitWidth + 12
                    height: badge_row.implicitHeight + 6
                    radius: Style.px(4)
                    color: Qt.alpha(Theme.bg_shadow, 0.85)
                    border.width: 1
                    border.color: root.st.text_accent

                    Row {
                        id: badge_row
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "\uf08d"
                            color: root.st.text_accent
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }

                        Text {
                            text: "Pinned"
                            color: root.st.text_accent
                            font.family: root.st.font_family
                            font.pixelSize: root.st.fs(-3)
                        }
                    }
                }
            }

            Text {
                id: preview_label
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: frame.bottom
                anchors.topMargin: 2
                text: (preview.pinned ? "Pinned" : "Showing") + (preview.path !== "" ? " · " + WallpaperSettings.base_name(preview.path) : "")
                elide: Text.ElideRight
                color: root.st.text_dim
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
            }
        }
    }
}
