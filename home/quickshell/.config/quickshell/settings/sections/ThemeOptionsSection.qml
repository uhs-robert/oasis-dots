// home/quickshell/.config/quickshell/settings/sections/ThemeOptionsSection.qml
import QtQuick
import QtQuick.Layouts
import "../../theme"
import ".."

RowsSection {
    id: root

    section_keys: "r reset style"
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

    readonly property var notes: ({
            device_model: "Which handheld is drawn: Color uses the palette, Original the grey shell.",
            scanlines: "Faint horizontal lines over popups and notifications.",
            glow: "A soft glow around text and frames.",
            glow_tint: "How strongly the glow shows, from 0 to 1.",
            dither: "A dotted pattern over the bar and cards.",
            meter_bloom: "A blurred copy of each meter drawn behind it.",
            caret_blink: "Blink the text cursor in search and input fields.",
            fade_fills: "Selection and title fills fade out to the right.",
            controller_glyphs: "Console buttons for keys: Labeled adds the key, D-pad only arrows and shoulders.",
            watch_colors: "Theme tints the watch from your palette. Classic is the fixed lock-skin green.",
            picker_skin: "Screenshot picker cursor, loupe and targets, from any style, in your palette.",
            overview_skin: "Overview extras: Night Vision's counter, tint and lock-on, or MGS1 Scope's reticle.",
            osd_layout: "Volume and brightness OSD. Watch Dial also adds dials to Volume and Battery.",
            weather_header: "Weather header and Daily view, from any style, drawn in your palette.",
            done_anim: "The keeptabs celebration when a session finishes, from any style.",
            wait_anim: "The keeptabs cue when a session waits on you, from any style.",
            toast_enter: "How notification toasts arrive, from any style.",
            workspace_art: "The bar's workspace indicator, from any style, drawn in your palette.",
            font_family: "Font for popups and most text. Each style has its own default.",
            bar_font_family: "Font for the bar. Each style has its own default.",
            font_size: "Base text size in pixels; other sizes scale from it."
        })

    function row_for(def) {
        const kind = def.type;
        return {
            label: def.label,
            desc: root.notes[def.key] || "",
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
