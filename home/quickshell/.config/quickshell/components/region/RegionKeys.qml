// home/quickshell/.config/quickshell/components/region/RegionKeys.qml
pragma ComponentBehavior: Bound
import QtQuick
import "../../theme"
import "../../services"

// Key handling for the region selector: cursor moves, anchors, toolbar and the pick keys.
Item {
    id: root

    required property bool keyboard_owner
    required property bool pixel_mode
    required property bool target_mode
    required property bool sharing

    signal help_requested()
    signal run_tool(int index)

    function cursor_key() {
        return Screenshot.target_index + "|" + Screenshot.tool_index;
    }
    function play_if_moved(before) {
        if (root.cursor_key() !== before) ThemeAudio.play("cursor");
    }

    anchors.fill: parent
    focus: root.keyboard_owner
    Component.onCompleted: if (root.keyboard_owner) root.forceActiveFocus()

    // Direction keys held down, so two of them move the cursor diagonally like the Cursor submap.
    property var held: ({})

    readonly property string phase: Screenshot.phase
    onPhaseChanged: root.held = {}

    Keys.onReleased: event => {
        if (!event.isAutoRepeat) delete root.held[event.key];
    }

    Keys.onPressed: event => {
        const before = root.cursor_key();
        const shift = event.modifiers & Qt.ShiftModifier;
        const ctrl = event.modifiers & Qt.ControlModifier;
        // The Cursor submap's tiers: 10px, Shift 100, Ctrl 1, Ctrl+Shift 300.
        const step = ctrl && shift ? 300 : shift ? 100 : ctrl ? 1 : 10;
        const toolbar = Screenshot.phase === "toolbar";
        const typed = toolbar ? Screenshot.actions.findIndex(a => a.key === event.text) : -1;
        const dir = { [Qt.Key_H]: [-1, 0], [Qt.Key_Left]: [-1, 0], [Qt.Key_L]: [1, 0], [Qt.Key_Right]: [1, 0], [Qt.Key_K]: [0, -1], [Qt.Key_Up]: [0, -1], [Qt.Key_J]: [0, 1], [Qt.Key_Down]: [0, 1] }[event.key];
        if (Screenshot.phase === "capture") {
            return;
        } else if (event.key === Qt.Key_Question || event.text === "?") {
            root.help_requested();
        } else if (event.key === Qt.Key_Escape) {
            ThemeAudio.play("cancel");
            if (toolbar) Screenshot.reselect();
            else if (Screenshot.anchored) Screenshot.clear_anchor();
            else if (root.sharing) Screenshot.share_back();
            else Screenshot.cancel();
        } else if (event.key === Qt.Key_Q) {
            ThemeAudio.play("cancel");
            Screenshot.cancel();
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal || event.text === "+" || event.text === "=") {
            Screenshot.step_zoom(1);
        } else if (event.key === Qt.Key_Minus || event.text === "-") {
            Screenshot.step_zoom(-1);
        } else if (event.key === Qt.Key_BracketLeft || event.text === "[") {
            Screenshot.step_lens(-1);
        } else if (event.key === Qt.Key_BracketRight || event.text === "]") {
            Screenshot.step_lens(1);
        } else if (!toolbar && !shift && (event.key === Qt.Key_I || event.key === Qt.Key_O)) {
            Screenshot.step_zoom(event.key === Qt.Key_I ? 1 : -1);
        } else if (event.key === Qt.Key_M && !shift) {
            Screenshot.lens_on = !Screenshot.lens_on;
        } else if (root.pixel_mode && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            ThemeAudio.play("confirm");
            Screenshot.pick_pixel();
        } else if ((toolbar || root.target_mode) && !Screenshot.frozen && event.key === Qt.Key_D) {
            Screenshot.cycle_delay();
        } else if (!toolbar && root.target_mode && dir) {
            Screenshot.step_target(dir[0], dir[1]);
            root.play_if_moved(before);
        } else if (!toolbar && root.target_mode && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            Screenshot.cycle_target(event.key === Qt.Key_Backtab || shift ? -1 : 1);
            root.play_if_moved(before);
        } else if (!toolbar && root.target_mode && Style.picker_skin === "tiecomp" && event.key === Qt.Key_T && !ctrl) {
            Screenshot.cycle_target(shift ? -1 : 1);
            root.play_if_moved(before);
        } else if (!toolbar && root.target_mode && event.text !== "" && Style.picker_hint_keys.indexOf(event.text) >= 0 && Style.picker_hint_keys.indexOf(event.text) < Screenshot.targets.length) {
            Screenshot.highlight(Style.picker_hint_keys.indexOf(event.text));
            ThemeAudio.play("confirm");
            Screenshot.confirm();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (toolbar) {
                root.run_tool(Screenshot.tool_index);
            } else if (Screenshot.anchored || Screenshot.has_selection || root.target_mode) {
                ThemeAudio.play("confirm");
                Screenshot.confirm();
            } else {
                Screenshot.select_screen(Screenshot.cursor_screen);
                ThemeAudio.play("confirm");
                Screenshot.confirm();
            }
        } else if (typed >= 0) {
            root.run_tool(typed);
        } else if (toolbar && event.key === Qt.Key_Backspace) {
            ThemeAudio.play("cancel");
            Screenshot.reselect();
        } else if (toolbar && dir && dir[0] !== 0) {
            Screenshot.tool_index = (Screenshot.tool_index + dir[0] + Screenshot.actions.length) % Screenshot.actions.length;
            root.play_if_moved(before);
        } else if (toolbar && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            const delta = event.key === Qt.Key_Backtab || shift ? -1 : 1;
            Screenshot.tool_index = (Screenshot.tool_index + delta + Screenshot.actions.length) % Screenshot.actions.length;
            root.play_if_moved(before);
        } else if (!toolbar && dir) {
            root.held[event.key] = dir;
            let dx = 0;
            let dy = 0;
            for (const k in root.held) {
                dx += root.held[k][0];
                dy += root.held[k][1];
            }
            Screenshot.move_cursor(Math.sign(dx) * step, Math.sign(dy) * step);
        } else if (!toolbar && !root.pixel_mode && !root.target_mode && (event.key === Qt.Key_V || event.key === Qt.Key_Space)) {
            if (event.key === Qt.Key_Space && event.isAutoRepeat) {
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Space && Screenshot.anchored) {
                ThemeAudio.play("confirm");
                Screenshot.confirm();
            } else {
                Screenshot.toggle_anchor();
            }
        } else if (!toolbar && !root.pixel_mode && !root.target_mode && shift && event.key === Qt.Key_O) {
            Screenshot.swap_anchor();
        } else {
            return;
        }
        event.accepted = true;
    }
}
