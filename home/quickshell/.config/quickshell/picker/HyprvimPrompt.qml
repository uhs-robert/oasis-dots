// home/quickshell/.config/quickshell/picker/HyprvimPrompt.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../components"
import "../theme"
import "../services"
import "Fuzzy.js" as Fuzzy

// HyprVim's prompt bar over its `hyprvim_prompt` IPC target, docked at the bottom in the active style.
// HyprVim stays authoritative: the bar only edits a line, then writes it to result_path and dispatches the callback.
Popup {
    id: root

    popup_name: "hyprvim_prompt"
    size_class: "large"
    dock_bottom: true
    anim_scale: 0.3
    title: String(root.spec.title || "Prompt").toUpperCase()
    footer_hint: root.is_output ? "j/k scroll · Ctrl+d/u half page · gg/G top/bottom · Enter/Esc/q close" : "Enter run · Esc normal · q close"
    footer_override: !root.is_output && root.insert ? "Enter run · Tab complete · Esc normal" : ""
    key_help: root.is_output ? "" : ["Enter run", "Tab/Shift+Tab complete", "Up/Down history", "Ctrl+p/n history", "Ctrl+u clear to start", "Ctrl+w delete word", "Esc normal mode", "h/l char", "w/b/e word", "0/^/$ start/first/end", "x/X delete char", "D/C delete/change to end", "dd/cc clear line", "d/c+motion delete/change", "r replace char", "u undo", "i/a insert/append", "I/A insert at start/end", "j/k menu, or history on an empty line", "gg/G first/last completion", "Enter accept completion or run", "q/Esc cancel"].join(" · ")

    readonly property int max_output: 100000
    readonly property int max_items: 200

    property var spec: ({})
    // True from open until the callback is dispatched; the callback fires exactly once per spec.
    property bool session: false
    // [text or null, result_path, callback] waiting for the bar to unmap, as the terminal's exit would.
    property var pending: null
    readonly property bool is_open: Popups.open_name === root.popup_name
    readonly property bool is_output: root.spec.kind === "output"
    readonly property real screen_height: root.screen ? root.screen.height : 1080
    readonly property real row_height: Style.px(26)
    readonly property real input_height: Style.px(30)

    // Tab cycling previews candidates in the line; the menu keeps ranking what was typed before it.
    property var cycle_base: null
    property int selected: -1
    property bool menu_hidden: false
    property bool applying: false
    property int history_index: -1
    property string draft: ""
    property string output_text: ""
    property bool insert: true
    // A typed operator or prefix waiting for its second key: d, c, r or g.
    property string pending_key: ""
    property var undo_stack: []
    // First visible menu row; the menu is a fixed window of slots over items.
    property int menu_top: 0
    // Latched per prompt once shown: menu slots are built once, and the hint line keeps its place.
    property bool menu_reserved: false
    property bool hint_reserved: false
    // Set when Enter is held back for a missing argument; cleared by the next edit.
    property string warn_text: ""

    // Keyed "cmd|pos|prev_args"; a source runs once per key per prompt.
    property var source_cache: ({})
    property var source_queue: []
    property var shell_items: null
    // Last source and query with every match, so a query that only grew filters those instead of the whole source.
    readonly property var memo: ({ key: "", cur: "", matched: [] })

    readonly property string query_text: root.cycle_base !== null ? root.cycle_base : input.text
    readonly property var ctx: root.context_of(root.query_text)
    readonly property var arg_spec: root.ctx.kind === "arg" ? root.arg_spec_for(root.ctx.cmd, root.ctx.pos) : null
    // While Tab previews a command, the hint already speaks for its first argument.
    readonly property var hint_ctx: root.cycle_base !== null && root.ctx.kind === "command" ? root.context_of(input.text) : root.ctx
    readonly property var hint_spec: root.hint_ctx.kind === "arg" ? root.arg_spec_for(root.hint_ctx.cmd, root.hint_ctx.pos) : null
    readonly property string hint: root.hint_spec && root.hint_spec.hint ? root.hint_spec.hint : ""
    readonly property bool loading: root.ctx.kind === "shell" && root.shell_items === null || !!root.arg_spec && !!root.arg_spec.source && root.source_cache[root.source_key()] === undefined
    readonly property var items: root.candidates(root.ctx, root.source_cache, root.shell_items)
    readonly property bool menu_shown: !root.is_output && !root.menu_hidden && root.items.length > 0 && (root.query_text !== "" || root.cycle_base !== null)
    readonly property int menu_slots: Math.min(10, Math.max(3, Math.floor(root.screen_height * 0.35 / root.row_height)))
    readonly property int menu_rows: root.menu_shown ? Math.min(root.items.length - root.menu_top, root.menu_slots) : 0
    // The usage column sits between name and description; a narrow bar collapses it to a dim ellipsis.
    readonly property bool usage_column: root.ctx.kind === "command" && root.items.some(e => !!e.item.usage)
    readonly property bool hint_shown: !root.is_output && (root.hint !== "" || root.loading || root.warn_text !== "")
    readonly property real output_height: Math.min(output_view.contentHeight + 8, Math.round(root.screen_height * 0.45))

    readonly property real menu_height: root.menu_slots * root.row_height + 8
    // The surface holds the tallest input layout from open; the panel grows inside it as the menu appears.
    reserve_height: root.is_output ? 0 : root.input_height + hint_text.height + 6 + root.menu_height + 24
    body_height: root.is_output
        ? output_label.height + 8 + root.output_height + 24
        : root.input_height + (root.hint_reserved ? hint_text.height + 6 : 0) + (root.menu_shown ? root.menu_height : 0) + 24

    onCtxChanged: root.request_sources()
    onItemsChanged: {
        root.menu_top = 0;
        root.reveal_selected();
    }
    onMenu_shownChanged: if (root.menu_shown) root.menu_reserved = true
    onHint_shownChanged: if (root.hint_shown) root.hint_reserved = true
    onIs_openChanged: {
        if (root.is_open) Qt.callLater(root.focus_body);
        else if (root.session) root.finish(null);
    }
    onVisibleChanged: if (!visible) root.flush()
    // A config reload mid-prompt must still answer, or HyprVim never restores the mode.
    Component.onDestruction: {
        root.finish(null);
        root.flush();
    }

    IpcHandler {
        target: "hyprvim_prompt"

        // Returns "ok" once the prompt is shown; HyprVim falls back to its terminal bar on anything else.
        function open(path: string): string {
            return root.open_spec(path);
        }

        function close(): void {
            if (root.session) root.finish(null);
        }
    }

    Timer {
        id: warn_timer
        interval: 2000
        onTriggered: root.warn_text = ""
    }

    // blockLoading does not block once a file has loaded, so a new path would read the previous file.
    FileView {
        id: spec_file
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: output_file
        blockAllReads: true
        printErrors: false
    }

    Process {
        id: source_proc
        property string key: ""
        stdout: StdioCollector {
            // a stale result can still arrive right after finish() stops the process
            onStreamFinished: {
                if (!root.session) return;
                const next = Object.assign({}, root.source_cache);
                next[source_proc.key] = root.parse_source(text);
                root.source_cache = next;
                root.run_next_source();
            }
        }
    }

    Process {
        id: shell_proc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.session) return;
                root.shell_items = text.split("\n").filter(l => l !== "").map(l => ({ label: l, description: "", insert: l + " " }));
            }
        }
    }

    function open_spec(path) {
        if (root.session) root.finish(null);
        root.flush();
        spec_file.path = path;
        let parsed;
        try {
            parsed = JSON.parse(spec_file.text());
        } catch (e) {
            console.warn("hyprvim_prompt: invalid spec (" + e + ")");
            return "invalid";
        }
        if (!parsed || !parsed.callback) return "invalid";
        root.spec = parsed;
        root.session = true;
        root.cycle_base = null;
        root.selected = -1;
        root.menu_hidden = false;
        root.history_index = -1;
        root.draft = "";
        root.source_cache = {};
        root.source_queue = [];
        root.shell_items = null;
        root.output_text = "";
        root.menu_top = 0;
        root.menu_reserved = false;
        root.hint_reserved = false;
        root.warn_text = "";
        root.memo.key = "";
        root.memo.matched = [];
        root.insert = true;
        root.pending_key = "";
        root.undo_stack = [];
        if (root.is_output) {
            output_file.path = parsed.output_path || "";
            const text = output_file.text() || "";
            root.output_text = text.length > root.max_output ? text.slice(0, root.max_output) + "\n[output truncated]" : text.replace(/\n+$/, "");
            output_view.contentY = 0;
        }
        root.set_text(parsed.text || "");
        root.snapshot();
        const mon = Hyprland.focusedMonitor;
        const screen = (mon && Quickshell.screens.find(s => s.name === mon.name)) || Quickshell.screens[0];
        Popups.open(root.popup_name, null, Theme.bg_mantle, screen ? screen.name : "");
        return "ok";
    }

    // Cancel is result null: HyprVim reads a missing result file as no input.
    function finish(result) {
        if (!root.session) return;
        root.session = false;
        root.source_queue = [];
        if (source_proc.running) source_proc.running = false;
        if (shell_proc.running) shell_proc.running = false;
        root.pending = [result, root.spec.result_path || "", root.spec.callback];
        if (root.is_open) Popups.close();
        if (!root.visible) root.flush();
    }

    function flush() {
        const p = root.pending;
        if (!p) return;
        root.pending = null;
        if (p[0] !== null && p[1] !== "") Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"; exec hyprctl dispatch \"$3\"", "sh", p[0], p[1], p[2]]);
        else Quickshell.execDetached(["hyprctl", "dispatch", p[2]]);
    }

    function focus_body() {
        if (!root.is_open) return;
        if (root.is_output) output_scope.forceActiveFocus();
        else if (root.insert) input.forceActiveFocus();
        else input_scope.forceActiveFocus();
    }

    function set_text(text) {
        root.applying = true;
        input.text = text;
        input.cursorPosition = root.insert ? text.length : root.normal_max();
        root.applying = false;
    }

    function normal_max() {
        return Math.max(0, input.text.length - 1);
    }

    function snapshot() {
        root.undo_stack = root.undo_stack.slice(-49).concat([{ text: input.text, pos: input.cursorPosition }]);
    }

    function undo() {
        const s = root.undo_stack[root.undo_stack.length - 1];
        if (!s) return;
        root.undo_stack = root.undo_stack.slice(0, -1);
        input.text = s.text;
        input.cursorPosition = Math.min(s.pos, root.normal_max());
    }

    // An insert session is one undo step, like vim; `record` is false when an edit already snapshotted.
    function enter_insert(pos, record) {
        if (record) root.snapshot();
        root.pending_key = "";
        root.insert = true;
        input.cursorPosition = Math.max(0, Math.min(pos, input.text.length));
        input.forceActiveFocus();
    }

    function enter_normal() {
        const top = root.undo_stack[root.undo_stack.length - 1];
        if (top && top.text === input.text) root.undo_stack = root.undo_stack.slice(0, -1);
        const pos = input.cursorPosition;
        root.insert = false;
        root.pending_key = "";
        input.focus = false;
        input_scope.forceActiveFocus();
        input.cursorPosition = Math.min(Math.max(0, pos - 1), root.normal_max());
    }

    // Vim word classes: blank, keyword characters, other punctuation.
    function char_class(c) {
        return /\s/.test(c) ? 0 : /\w/.test(c) ? 1 : 2;
    }

    function word_forward(t, p) {
        const n = t.length;
        const c = p < n ? root.char_class(t[p]) : 0;
        if (c !== 0) while (p < n && root.char_class(t[p]) === c) p++;
        while (p < n && root.char_class(t[p]) === 0) p++;
        return p;
    }

    function word_end(t, p) {
        const n = t.length;
        p++;
        while (p < n && root.char_class(t[p]) === 0) p++;
        if (p >= n) return Math.max(0, n - 1);
        const c = root.char_class(t[p]);
        while (p + 1 < n && root.char_class(t[p + 1]) === c) p++;
        return p;
    }

    function word_back(t, p) {
        if (p <= 0) return 0;
        p--;
        while (p > 0 && root.char_class(t[p]) === 0) p--;
        const c = root.char_class(t[p]);
        while (p > 0 && root.char_class(t[p - 1]) === c) p--;
        return p;
    }

    // Where a motion lands from p, and whether an operator over it includes the landing character.
    function motion(ch, t, p) {
        const n = t.length;
        if (ch === "h") return { to: Math.max(0, p - 1), incl: false };
        if (ch === "l") return { to: Math.min(n, p + 1), incl: false };
        if (ch === "w") return { to: root.word_forward(t, p), incl: false };
        if (ch === "b") return { to: root.word_back(t, p), incl: false };
        if (ch === "e") return { to: root.word_end(t, p), incl: true };
        if (ch === "0") return { to: 0, incl: false };
        if (ch === "^") return { to: Math.max(0, t.search(/\S/)), incl: false };
        if (ch === "$") return { to: Math.max(0, n - 1), incl: true };
        return null;
    }

    function remove(from, to) {
        const t = input.text;
        if (from >= to || from >= t.length) return;
        root.snapshot();
        input.text = t.slice(0, from) + t.slice(to);
        input.cursorPosition = from;
    }

    function operate(op, ch) {
        const t = input.text;
        const p = input.cursorPosition;
        let from = p;
        let to = t.length;
        if (ch !== op) {
            // cw on a word changes to its end, as in vim.
            const m = op === "c" && ch === "w" && p < t.length && root.char_class(t[p]) !== 0 ? { to: root.word_end(t, p), incl: true } : root.motion(ch, t, p);
            if (!m) return;
            from = Math.min(p, m.to);
            to = Math.min(t.length, Math.max(p, m.to) + (m.incl ? 1 : 0));
        } else {
            from = 0;
        }
        if (op === "c") {
            root.snapshot();
            input.text = t.slice(0, from) + t.slice(to);
            root.enter_insert(from, false);
        } else {
            root.remove(from, to);
            input.cursorPosition = Math.min(from, root.normal_max());
        }
    }

    function replace_char(ch) {
        const t = input.text;
        const p = input.cursorPosition;
        if (p >= t.length) return;
        root.snapshot();
        input.text = t.slice(0, p) + ch + t.slice(p + 1);
        input.cursorPosition = p;
    }

    // What the cursor is completing: a command name, a command's Nth argument, or a shell command after `!`.
    function context_of(line) {
        let head = "";
        let seg = line;
        if (root.spec.chain && !/^(?:!|silent\s+!|%?s\/)/.test(line)) {
            const cut = line.lastIndexOf("|");
            if (cut >= 0) {
                const rest = line.slice(cut + 1);
                const lead = rest.match(/^\s*/)[0];
                head = line.slice(0, cut + 1) + lead;
                seg = rest.slice(lead.length);
            }
        }
        const shell = seg.match(/^((?:silent\s+)?!)(\S*)$/);
        if (shell) return root.spec.shell_source ? { kind: "shell", head: head + shell[1], cur: shell[2] } : { kind: "none" };
        if (/^(?:silent\s+)?!/.test(seg) || /^%?s\//.test(seg)) return { kind: "none" };
        const space = seg.indexOf(" ");
        if (space < 0) return { kind: "command", head: head, cur: seg };
        const words = seg.slice(space + 1).split(/\s+/).filter(w => w !== "");
        const trailing = /\s$/.test(seg);
        const cur = trailing ? "" : words[words.length - 1] || "";
        const pos = trailing ? words.length + 1 : words.length;
        return { kind: "arg", head: head + seg.slice(0, seg.length - cur.length), cmd: seg.slice(0, space), pos: pos, cur: cur, prev: words.slice(0, pos - 1).join(" ") };
    }

    function canonical(cmd) {
        const args = root.spec.args || {};
        if (args[cmd]) return cmd;
        const entry = (root.spec.completions || []).find(c => (c.aliases || []).indexOf(cmd) >= 0);
        return entry ? entry.name : cmd;
    }

    function arg_spec_for(cmd, pos) {
        const positions = (root.spec.args || {})[root.canonical(cmd)];
        return positions && pos >= 1 && pos <= positions.length ? positions[pos - 1] : null;
    }

    function entry_for(cmd) {
        return (root.spec.completions || []).find(c => c.name === cmd || (c.aliases || []).indexOf(cmd) >= 0) || null;
    }

    // First required argument the line leaves empty, or 0. A spec without min_args never holds Enter.
    function missing_pos(c) {
        if (c.kind !== "command" && c.kind !== "arg") return 0;
        const entry = root.entry_for(c.kind === "command" ? c.cur : c.cmd);
        const need = entry && entry.min_args > 0 ? entry.min_args : 0;
        const filled = c.kind === "command" ? 0 : c.cur !== "" ? c.pos : c.pos - 1;
        return filled < need ? filled + 1 : 0;
    }

    function settle() {
        root.cycle_base = null;
        root.selected = -1;
        root.menu_hidden = false;
        if (!root.insert) input.cursorPosition = root.normal_max();
    }

    // Enter runs the line unless its command still needs an argument; then it steps toward that argument.
    function press_enter() {
        const line = input.text;
        const c = root.context_of(line);
        const need = root.missing_pos(c);
        if (root.cycle_base !== null && root.selected >= 0 && (!root.insert || need > 0 || root.ctx.kind === "arg")) {
            root.settle();
            return;
        }
        if (need === 0) {
            root.finish(line);
            return;
        }
        if (!/\s$/.test(line)) root.set_text(line + " ");
        root.settle();
        const cmd = c.kind === "command" ? c.cur : c.cmd;
        const entry = root.entry_for(cmd);
        const spec = root.arg_spec_for(cmd, need);
        root.warn_text = entry && entry.usage ? ":" + cmd + " needs: " + entry.usage : ":" + cmd + " arg " + need + " needs: " + (spec && spec.hint ? spec.hint : "a value");
        warn_timer.restart();
    }

    function source_key() {
        return root.ctx.kind === "arg" ? root.canonical(root.ctx.cmd) + "|" + root.ctx.pos + "|" + root.ctx.prev : "";
    }

    function request_sources() {
        if (!root.session || root.is_output) return;
        if (root.ctx.kind === "shell" && root.shell_items === null && !shell_proc.running) {
            shell_proc.command = ["bash", "-c", root.spec.shell_source];
            shell_proc.running = true;
        }
        const spec = root.arg_spec;
        if (!spec || !spec.source) return;
        const key = root.source_key();
        if (root.source_cache[key] !== undefined || root.source_queue.some(q => q.key === key)) return;
        root.source_queue = root.source_queue.concat([{ key: key, source: spec.source, prev: root.ctx.prev }]);
        if (!source_proc.running) root.run_next_source();
    }

    function run_next_source() {
        if (root.source_queue.length === 0) return;
        const next = root.source_queue[0];
        root.source_queue = root.source_queue.slice(1);
        source_proc.key = next.key;
        source_proc.environment = { HV_ARGS: next.prev };
        source_proc.command = ["bash", "-c", next.source];
        source_proc.running = true;
    }

    // "value<TAB>description[<TAB>insert]" lines; a line with no value is not a candidate.
    function parse_source(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const f = line.split("\t");
            const value = f[0].trim();
            if (value === "") continue;
            out.push({ label: value, description: f[1] || "", insert: (f[2] || value) + " " });
        }
        return out;
    }

    // Matching is monotonic: whatever matches a longer query also matched its prefix.
    function narrowed_base(key, list, cur) {
        const m = root.memo;
        const base = m.key === key && cur.startsWith(m.cur) ? m.matched : list;
        m.key = key;
        m.cur = cur;
        return base;
    }

    function rank(key, list, query) {
        const terms = Fuzzy.terms_of(query);
        const base = root.narrowed_base(key, list, query);
        if (terms.length === 0) {
            root.memo.matched = base;
            return base.slice(0, root.max_items).map(item => ({ item: item, positions: [] }));
        }
        const out = [];
        const matched = [];
        for (const item of base) {
            const m = Fuzzy.score_item(terms, item);
            if (!m) continue;
            out.push({ item: item, positions: m.positions, score: m.score });
            matched.push(item);
        }
        root.memo.matched = matched;
        out.sort((a, b) => b.score - a.score || a.item.label.length - b.item.label.length);
        return out.slice(0, root.max_items);
    }

    function candidates(ctx, cache, shell_items) {
        if (!root.session || root.is_output) return [];
        if (ctx.kind === "command") {
            const list = (root.spec.completions || []).map(c => ({ label: c.name, usage: c.usage || "", description: c.desc || "", keywords: c.aliases || [], insert: c.name + (c.takes_args ? " " : "") }));
            return root.rank("command", list, ctx.cur);
        }
        if (ctx.kind === "shell") {
            const base = root.narrowed_base("shell|" + (shell_items !== null), shell_items || [], ctx.cur);
            const list = base.filter(i => i.label.startsWith(ctx.cur));
            root.memo.matched = list;
            return list.slice(0, root.max_items).map(item => ({ item: item, positions: [...Array(ctx.cur.length).keys()] }));
        }
        if (ctx.kind !== "arg") return [];
        const spec = root.arg_spec_for(ctx.cmd, ctx.pos);
        if (!spec) return [];
        const key = root.canonical(ctx.cmd) + "|" + ctx.pos + "|" + ctx.prev;
        const sourced = spec.source ? cache[key] : undefined;
        let list = (spec.values || []).map(v => ({ label: v[0], description: v[1] || "", insert: v[0] + " " }));
        if (sourced) list = list.concat(sourced);
        return root.rank("arg|" + key + "|" + (sourced !== undefined), list, ctx.cur);
    }

    function apply(index) {
        const entry = root.items[index];
        if (!entry) return;
        root.set_text(root.ctx.head + entry.item.insert);
    }

    function cycle(delta) {
        const n = root.items.length;
        if (n === 0) return;
        if (root.cycle_base === null) {
            if (n === 1) {
                root.menu_hidden = false;
                root.apply(0);
                return;
            }
            root.cycle_base = input.text;
            root.menu_hidden = false;
            root.selected = delta > 0 ? 0 : n - 1;
        } else {
            root.selected = ((root.selected + delta) % n + n) % n;
        }
        root.reveal_selected();
        root.apply(root.selected);
    }

    function select_item(i) {
        const n = root.items.length;
        if (n === 0) return;
        if (root.cycle_base === null) root.cycle_base = input.text;
        root.menu_hidden = false;
        root.selected = Math.max(0, Math.min(n - 1, i));
        root.reveal_selected();
        root.apply(root.selected);
    }

    // j/k walk history on an empty line and keep walking while the line came from history; otherwise the menu.
    function walk(delta) {
        if (input.text === "" || root.history_index !== -1) root.recall(delta);
        else root.cycle(delta);
    }

    function reveal_selected() {
        if (root.selected < 0) return;
        if (root.selected < root.menu_top) root.menu_top = root.selected;
        else if (root.selected >= root.menu_top + root.menu_slots) root.menu_top = root.selected - root.menu_slots + 1;
    }

    function scroll_menu(delta) {
        root.menu_top = Math.max(0, Math.min(root.items.length - root.menu_slots, root.menu_top + delta));
    }

    function recall(delta) {
        const history = root.spec.history || [];
        if (history.length === 0) return;
        if (root.history_index === -1) {
            if (delta > 0) return;
            root.draft = input.text;
            root.history_index = history.length;
        }
        const next = root.history_index + delta;
        if (next < 0) return;
        root.cycle_base = null;
        root.selected = -1;
        root.menu_hidden = true;
        if (next >= history.length) {
            root.history_index = -1;
            root.set_text(root.draft);
        } else {
            root.history_index = next;
            root.set_text(history[next]);
        }
    }

    function delete_word() {
        const pos = input.cursorPosition;
        const before = input.text.slice(0, pos).replace(/\S+\s*$|\s+$/, "");
        input.text = before + input.text.slice(pos);
        input.cursorPosition = before.length;
    }

    function handle_input_key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.press_enter();
        } else if (k === Qt.Key_Escape) {
            root.enter_normal();
        } else if (k === Qt.Key_Tab) {
            root.cycle(1);
        } else if (k === Qt.Key_Backtab) {
            root.cycle(-1);
        } else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_P)) {
            root.recall(-1);
        } else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) {
            root.recall(1);
        } else if (ctrl && k === Qt.Key_U) {
            input.text = input.text.slice(input.cursorPosition);
            input.cursorPosition = 0;
        } else if (ctrl && k === Qt.Key_W) {
            root.delete_word();
        } else {
            return;
        }
        event.accepted = true;
    }

    function handle_normal_key(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const k = event.key;
        const t = event.text;
        const p = input.cursorPosition;
        if (k === Qt.Key_Shift || k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Meta) return;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            root.press_enter();
        } else if (k === Qt.Key_Escape) {
            if (root.pending_key !== "") root.pending_key = "";
            else root.finish(null);
        } else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_P)) {
            root.recall(-1);
        } else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) {
            root.recall(1);
        } else if (k === Qt.Key_Tab) {
            root.cycle(1);
        } else if (k === Qt.Key_Backtab) {
            root.cycle(-1);
        } else if (ctrl || (event.modifiers & Qt.AltModifier)) {
            return;
        } else if (root.pending_key !== "") {
            const op = root.pending_key;
            root.pending_key = "";
            if (op === "r" && t.length === 1 && t >= " ") root.replace_char(t);
            else if (op === "g" && t === "g") root.select_item(0);
            else if (op === "d" || op === "c") root.operate(op, t);
        } else if (k === Qt.Key_Left || k === Qt.Key_Right || "hlwbe0^$".indexOf(t) >= 0 && t !== "") {
            const m = root.motion(k === Qt.Key_Left ? "h" : k === Qt.Key_Right ? "l" : t, input.text, p);
            input.cursorPosition = Math.min(m.to, root.normal_max());
        } else if (t === "x") {
            root.remove(p, p + 1);
            input.cursorPosition = Math.min(p, root.normal_max());
        } else if (t === "X") {
            if (p > 0) root.remove(p - 1, p);
        } else if (t === "D") {
            root.operate("d", "$");
        } else if (t === "C") {
            root.operate("c", "$");
        } else if (t === "d" || t === "c" || t === "r" || t === "g") {
            root.pending_key = t;
        } else if (t === "G") {
            root.select_item(root.items.length - 1);
        } else if (t === "i") {
            root.enter_insert(p, true);
        } else if (t === "a") {
            root.enter_insert(p + 1, true);
        } else if (t === "I") {
            root.enter_insert(Math.max(0, input.text.search(/\S/)), true);
        } else if (t === "A") {
            root.enter_insert(input.text.length, true);
        } else if (t === "j") {
            root.walk(1);
        } else if (t === "k") {
            root.walk(-1);
        } else if (t === "u") {
            root.undo();
        } else if (t === "q") {
            root.finish(null);
        } else {
            return;
        }
        event.accepted = true;
    }

    function scroll_output(dy) {
        const max = Math.max(0, output_view.contentHeight - output_view.height);
        output_view.contentY = Math.max(0, Math.min(max, output_view.contentY + dy));
    }

    onJump_first: output_view.contentY = 0
    onJump_last: root.scroll_output(output_view.contentHeight)
    jumps_enabled: root.is_output

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: 12
        clip: true

        FocusScope {
            id: input_scope
            anchors.fill: parent
            visible: !root.is_output
            focus: !root.is_output

            // NORMAL keys; the text input has focus only in INSERT.
            Keys.onPressed: event => root.handle_normal_key(event)

            // Fixed slots over a window of items: typing rebinds rows instead of recreating them.
            Column {
                id: menu
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: input_bar.top
                anchors.bottomMargin: 6 + (root.hint_reserved ? hint_text.height + 6 : 0)
                visible: root.menu_shown

                readonly property real label_width: Math.max(Style.px(160), menu.width * 0.3)
                readonly property bool usage_wide: menu.width >= Style.px(720)
                readonly property real usage_width: !root.usage_column ? 0 : menu.usage_wide ? Math.max(Style.px(150), menu.width * 0.2) : Style.px(14)

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => root.scroll_menu(event.angleDelta.y < 0 ? 1 : -1)
                }

                Repeater {
                    model: root.menu_reserved ? root.menu_slots : 0

                    delegate: Item {
                        id: menu_slot
                        required property int index
                        width: menu.width
                        height: root.row_height
                        visible: menu_slot.index < root.menu_rows

                        MenuRow {
                            id: row
                            readonly property int item_index: root.menu_top + menu_slot.index
                            readonly property var entry: root.items[row.item_index] || ({ item: { label: "", description: "" }, positions: [] })

                            width: menu.width
                            height: root.row_height - 2
                            selected: row.item_index === root.selected

                            Text {
                                id: row_label
                                x: 8 + row.inset
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, menu.label_width)
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: Fuzzy.highlight(row.entry.item.label, row.entry.positions, String(row.fg(root.st.text_accent)))
                                color: row.fg(root.st.text_fg)
                                font.family: root.st.mono_font
                                font.pixelSize: root.st.fs(-1)
                            }

                            Text {
                                x: 8 + row.inset + menu.label_width + 16
                                width: menu.usage_width
                                anchors.verticalCenter: parent.verticalCenter
                                visible: menu.usage_width > 0 && !!row.entry.item.usage
                                elide: Text.ElideRight
                                text: menu.usage_wide ? row.entry.item.usage || "" : "…"
                                color: row.fg(root.st.text_muted)
                                opacity: 0.7
                                font.family: root.st.mono_font
                                font.pixelSize: root.st.fs(-3)
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8 + row.inset + menu.label_width + 16 + (menu.usage_width > 0 ? menu.usage_width + 12 : 0)
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: row.entry.item.description
                                color: row.fg(root.st.text_muted)
                                font.family: root.st.font_family
                                font.pixelSize: root.st.fs(-3)
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.apply(row.item_index);
                                    root.settle();
                                    input.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            Text {
                id: hint_text
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: input_bar.top
                anchors.bottomMargin: 6
                visible: root.hint_shown
                elide: Text.ElideRight
                text: root.warn_text !== "" ? root.warn_text : root.loading && root.hint === "" ? "loading..." : ":" + (root.hint_ctx.cmd || "") + " arg " + (root.hint_ctx.pos || "") + ": " + root.hint + (root.loading ? "  (loading...)" : "")
                color: root.warn_text !== "" ? Theme.warning : root.st.text_muted
                font.family: root.st.font_family
                font.pixelSize: root.st.fs(-3)
            }

            Rectangle {
                id: input_bar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.input_height
                radius: Style.radius(4)
                color: Theme.bg_surface
                border.width: root.insert ? 1 : 0
                border.color: root.st.caret_color

                Text {
                    id: label_text
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.spec.label || ""
                    color: root.st.text_accent
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-1)
                    font.bold: true
                }

                TextInput {
                    id: input
                    anchors.left: label_text.right
                    anchors.leftMargin: label_text.text === "" ? 0 : 4
                    anchors.right: mode_text.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    clip: true
                    color: root.st.text_fg
                    selectionColor: root.st.selection_bg
                    selectedTextColor: root.st.selection_inverse ? root.st.selection_fg : root.st.text_fg
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-1)
                    onTextChanged: {
                        if (root.applying) return;
                        root.cycle_base = null;
                        root.selected = -1;
                        root.menu_hidden = false;
                        root.history_index = -1;
                        root.warn_text = "";
                    }
                    onActiveFocusChanged: if (activeFocus && !root.insert) root.enter_insert(input.cursorPosition, true)
                    // A static caret: the default one blinks for as long as the bar is open.
                    cursorDelegate: Rectangle {
                        width: 2
                        visible: input.activeFocus
                        color: root.st.caret_color
                    }

                    // Runs before TextInput's own handling, so Tab, Ctrl+U and Ctrl+W never reach it.
                    Keys.onPressed: event => root.handle_input_key(event)

                    FontMetrics {
                        id: cell_metrics
                        font: input.font
                    }

                    Rectangle {
                        id: block_cursor
                        readonly property string ch: input.text.charAt(input.cursorPosition)
                        visible: !root.insert && root.is_open
                        x: input.cursorRectangle.x
                        y: input.cursorRectangle.y
                        width: Math.max(2, cell_metrics.advanceWidth(block_cursor.ch || " "))
                        height: input.cursorRectangle.height
                        color: root.st.caret_color

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: block_cursor.ch
                            color: Theme.bg_surface
                            font: input.font
                        }
                    }
                }

                Text {
                    id: mode_text
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.insert ? "INSERT" : "NORMAL") + (root.menu_shown ? "  " + (root.selected >= 0 ? root.selected + 1 + "/" : "") + root.items.length : "")
                    color: root.insert ? root.st.text_accent : root.st.text_primary
                    font.family: root.st.font_family
                    font.pixelSize: root.st.fs(-4)
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: root.insert ? Qt.NoButton : Qt.LeftButton
                    cursorShape: Qt.IBeamCursor
                    onClicked: root.enter_insert(input.cursorPosition, true)
                }
            }
        }

        FocusScope {
            id: output_scope
            anchors.fill: parent
            visible: root.is_output
            focus: root.is_output

            Keys.onPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier;
                const k = event.key;
                const line = root.st.fs(4);
                if (k === Qt.Key_Return || k === Qt.Key_Enter) Popups.close();
                else if (k === Qt.Key_J || k === Qt.Key_Down) root.scroll_output(line);
                else if (k === Qt.Key_K || k === Qt.Key_Up) root.scroll_output(-line);
                else if (ctrl && k === Qt.Key_D || k === Qt.Key_PageDown) root.scroll_output(output_view.height / 2);
                else if (ctrl && k === Qt.Key_U || k === Qt.Key_PageUp) root.scroll_output(-output_view.height / 2);
                else return;
                event.accepted = true;
            }

            Text {
                id: output_label
                width: parent.width
                elide: Text.ElideRight
                text: (root.spec.label || "") + (root.spec.text || "")
                color: root.st.text_accent
                font.family: root.st.mono_font
                font.pixelSize: root.st.fs(-2)
                font.bold: true
            }

            Flickable {
                id: output_view
                y: output_label.height + 8
                width: parent.width
                height: root.output_height
                clip: true
                contentWidth: width
                contentHeight: output_text.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: output_text
                    width: output_view.width
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    text: root.output_text
                    color: root.st.text_fg
                    font.family: root.st.mono_font
                    font.pixelSize: root.st.fs(-3)
                }
            }
        }
    }
}
