// home/quickshell/.config/quickshell/settings/sections/WeatherSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../services"
import ".."

RowsSection {
    id: root

    readonly property var cfg: WeatherState.settings
    readonly property bool manual: String(root.cfg.latitude) !== "auto" && String(root.cfg.longitude) !== "auto"
    property string edit_key: ""
    property bool edit_invalid: false

    function choice_row(label, key, choices, names) {
        return {
            label: label,
            values: () => choices,
            text: v => names[v] || String(v),
            value: () => root.cfg[key],
            set: v => WeatherState.set_settings({ [key]: v }),
            pick: false
        };
    }

    function text_row(label, key, empty) {
        return {
            label: label,
            values: () => [],
            text: v => v === "" ? empty : v,
            value: () => root.cfg[key] === undefined ? "" : String(root.cfg[key]),
            set: v => {},
            cycle: false,
            edit: key,
            activate: () => root.start_edit(root.rows.find(r => r.edit === key))
        };
    }

    function set_mode(mode) {
        if (mode === "auto") {
            WeatherState.set_settings({ latitude: "auto", longitude: "auto" });
            return;
        }
        WeatherState.set_settings({ latitude: Number(WeatherState.lat.toFixed(4)), longitude: Number(WeatherState.lon.toFixed(4)) });
    }

    function build_rows() {
        const rows = [{
            label: "Location",
            values: () => ["auto", "manual"],
            text: v => v === "auto" ? "Automatic (IP lookup)" : "Manual",
            value: () => root.manual ? "manual" : "auto",
            set: v => root.set_mode(v),
            pick: false
        }];
        if (root.manual) {
            rows.push(root.text_row("Latitude", "latitude", ""));
            rows.push(root.text_row("Longitude", "longitude", ""));
            rows.push(root.text_row("Place name", "location_name", "Coordinates only"));
        }
        rows.push(root.choice_row("Units", "unit", ["fahrenheit", "celsius"], { fahrenheit: "Imperial (°F, mph, in)", celsius: "Metric (°C, km/h, mm)" }));
        rows.push({
            label: "Forecast days",
            values: () => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            text: v => String(v),
            value: () => Math.max(1, Math.min(16, Number(root.cfg.days) || 7)),
            set: v => WeatherState.set_settings({ days: v })
        });
        return rows;
    }

    function start_edit(row) {
        root.edit_key = row.edit;
        root.edit_invalid = false;
        input.text = row.value();
        input.forceActiveFocus();
        input.selectAll();
    }

    function end_edit() {
        root.edit_key = "";
        root.forceActiveFocus();
    }

    function commit_edit() {
        const text = input.text.trim();
        const key = root.edit_key;
        if (key === "location_name") {
            WeatherState.set_settings({ location_name: text === "" ? null : text });
        } else {
            const limit = key === "latitude" ? 90 : 180;
            const n = Number(text);
            if (!/^-?\d+(\.\d+)?$/.test(text) || Math.abs(n) > limit) {
                root.edit_invalid = true;
                return;
            }
            WeatherState.set_settings({ [key]: n });
        }
        root.end_edit();
    }

    rows: root.build_rows()
    onRowsChanged: root.cursor = Math.min(root.cursor, root.rows.length - 1)
    footer_hint: root.edit_key !== "" ? "Enter save · Ctrl+u clear · Esc cancel" : "j/k move · h/l change · Enter edit or list · Esc sections · q close"

    onFirst_key: event => {
        if (root.edit_key !== "") return;
        const row = root.rows[root.cursor];
        const open = event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_L || event.key === Qt.Key_Space;
        if (!row || !row.edit || !open) return;
        root.start_edit(row);
        event.accepted = true;
    }

    footer: ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Rectangle {
            visible: root.edit_key !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: Style.px(28)
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: root.edit_invalid ? root.st.text_primary : root.st.text_accent

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                maximumLength: 64
                clip: true
                color: root.st.text_fg
                selectionColor: root.st.text_accent
                font.family: root.st.font_family
                font.pixelSize: root.st.font_size
                onTextEdited: root.edit_invalid = false
                onActiveFocusChanged: if (!input.activeFocus && root.edit_key !== "") root.edit_key = ""

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) root.end_edit();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit_edit();
                    else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) input.text = "";
                    else return;
                    event.accepted = true;
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Automatic looks you up by IP address (ipwho.is). Weather alerts come from the US National Weather Service, so they only appear in the US. Saved to weather.local.json"
            wrapMode: Text.WordWrap
            color: root.st.text_dim
            font.family: root.st.font_family
            font.pixelSize: root.st.fs(-3)
        }
    }
}
