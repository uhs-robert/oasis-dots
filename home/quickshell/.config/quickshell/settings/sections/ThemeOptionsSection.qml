// home/quickshell/.config/quickshell/settings/sections/ThemeOptionsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import ".."

RowsSection {
    id: root

    footer_hint: "j/k move · H/L change · r reset style · h/Esc sections · q close"
    rows: Style.settings.map(def => root.row_for(def))

    function number_values(def) {
        const out = [];
        const count = Math.round((def.max - def.min) / def.step);
        for (let i = 0; i <= count; i++) out.push(Math.round((def.min + i * def.step) * 1000) / 1000);
        const now = Style.option(def.key);
        if (out.indexOf(now) < 0) out.push(now);
        return out.sort((a, b) => a - b);
    }

    function row_for(def) {
        const kind = def.type;
        return {
            label: def.label,
            values: () => kind === "bool" ? ["on", "off"] : kind === "choice" ? def.choices : root.number_values(def),
            text: v => def.labels ? def.labels[v] : String(v),
            value: () => kind === "bool" ? (Style.option(def.key) ? "on" : "off") : Style.option(def.key),
            set: v => Style.set_option(def.key, kind === "bool" ? v === "on" : v)
        };
    }

    onExtra_key: event => {
        if (event.key !== Qt.Key_R) return;
        Style.reset_options();
        event.accepted = true;
    }

    header: Text {
        Layout.fillWidth: true
        text: Style.label(Style.saved_name) + " options"
        color: root.st.text_dim
        font.family: root.st.font_family
        font.pixelSize: root.st.fs(-3)
    }
}
