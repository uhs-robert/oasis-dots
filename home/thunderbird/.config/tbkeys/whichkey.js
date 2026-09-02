// Which-key overlay for pending chord prefixes: chord trie/metadata, delay/
// timer state, and transient rendering. Never touches Mousetrap or tbkeys
// dispatch; its one non-passive act is suppressing a chord leader's native
// Thunderbird shortcut, which tbkeys itself cannot swallow. Loaded last, so
// it also fires the initial repaint once every module has populated window.tk.
(function (tk) {
  "use strict";

  // Explicit sequence -> label table, kept separate from keys.json so labels
  // stay human-written instead of derived from tk_* function names.
  const WHICHKEY_ENTRIES = [
    ["g f", "Focus folder tree"],
    ["g g", "Go to top"],
    ["g i", "Go to inbox"],
    ["g t", "Go to trash"],
    ["g d", "Go to drafts"],
    ["g m", "Focus message pane"],
    ["g s", "Go to sent"],
    ["g p", "Go to projects"],
    ["g o", "Find folder"],
    ["m R", "Mark all read"],
    ["m r", "Mark read"],
    ["m u", "Mark unread"],
    ["m j", "Toggle junk"],
    ["m s", "Mark starred"],
    ["m p", "Move to Projects"],
    ["z M", "Collapse all"],
    ["z R", "Expand all"],
    ["z z", "Scroll to center"],
    ["z t", "Scroll to top"],
    ["z b", "Scroll to bottom"],
    ["f u", "View unread"],
    ["f a", "View all"],
    ["f s", "Toggle starred filter"],
    ["t m", "Toggle message pane"],
    ["t f", "Toggle folder pane"],
    ["] u", "Next unread thread"],
    ["[ u", "Previous unread thread"],
    ["] U", "Next unread (any folder)"],
    ["[ U", "Previous unread (any folder)"],
    ["] s", "Next starred"],
    ["[ s", "Previous starred"],
    ["] t", "Next thread root"],
    ["[ t", "Previous thread root"],
    ["] a", "Next attachment"],
    ["[ a", "Previous attachment"],
    ["d d", "Delete"],
    ...[...tk.MARK_LETTERS].map((l) => [`M ${l}`, `Set folder mark ${l}`]),
    ...[...tk.MARK_LETTERS].map((l) => [`' ${l}`, `Jump to folder mark ${l}`]),
  ];

  /**
   * Builds a prefix trie from sequence/label pairs; each node holds `children`
   * (keyed by the next key) when it has descendants and `label` when a
   * sequence ends there. Supports chords of any depth, not just two keys.
   * @param {[string, string][]} entries - space-joined sequence to label pairs
   * @returns {Object} trie root node
   */
  tk.build_whichkey_trie = (entries) => {
    const root = {};
    for (const [seq, label] of entries) {
      let node = root;
      for (const key of seq.split(" ")) {
        node.children ??= {};
        node.children[key] ??= {};
        node = node.children[key];
      }
      node.label = label;
    }
    return root;
  };
  tk.whichkey_trie = tk.build_whichkey_trie(WHICHKEY_ENTRIES);
  tk.whichkey_node = tk.whichkey_trie;
  tk.whichkey_path = [];
  tk.whichkey_timer = null;
  tk.whichkey_full_shown = false;
  tk.suppress_keypress = null;

  // Group labels for the "?" full command list, shown as "+Label" per
  // leader key; only leaders that actually have children in the trie above.
  tk.whichkey_group_labels = {
    g: "Go",
    m: "Mark",
    z: "Scroll/Fold",
    f: "Filter view",
    t: "Toggle pane",
    "[": "Previous",
    "]": "Next",
    d: "Delete",
    M: "Set folder mark",
    "'": "Jump folder mark",
  };

  // Single-key (non-chord) bindings shown by "?" alongside the chord
  // leaders above; kept in sync with keys.json by hand, same as WHICHKEY_ENTRIES.
  const WHICHKEY_SINGLES = [
    ["esc", "Cancel / normal mode"],
    ["h", "Left / back"],
    ["j", "Down"],
    ["k", "Up"],
    ["l", "Right / open"],
    ["o", "Open message"],
    ["v", "Toggle visual mode"],
    ["F", "Forward"],
    ["r", "Reply"],
    ["R", "Reply all"],
    ["x", "Archive"],
    ["c", "New message"],
    ["q", "Close message / refresh"],
    ["u", "Undo"],
    ["/", "Search"],
    ["n", "Next search match"],
    ["N", "Previous search match"],
    [";", "Open conversation"],
    [":", "Command line"],
    ["G", "Go to bottom"],
    [".", "Repeat last action"],
    ["0-9", "Count prefix"],
    ["ctrl+h", "Close message / refresh"],
    ["ctrl+j", "Next tab"],
    ["ctrl+k", "Previous tab"],
    ["ctrl+l", "Open message"],
    ["ctrl+u", "Page up"],
    ["ctrl+d", "Page down"],
    ["ctrl+o", "Jump back"],
    ["ctrl+i", "Jump forward"],
    ["ctrl+x", "Close tab/window"],
    ["ctrl+c", "Close tab/window"],
    ["alt+h", "Focus thread tree"],
    ["alt+l", "Focus message pane"],
    ["shift+h", "Focus folder tree"],
    ["shift+l", "Focus thread tree"],
  ];

  // Mirrors the tag list in tbkeys' own stopCallback: several of these are
  // custom elements whose shadow DOM retargets events to the host.
  const WHICHKEY_TEXT_TAGS = new Set([
    "input",
    "textarea",
    "select",
    "textbox",
    "html:input",
    "html:textarea",
    "search-bar",
    "search-textbox",
    "xul:search-textbox",
    "global-search-bar",
    "moz-input-search",
    "account-hub-container",
    "imconversation",
  ]);

  // Held apart from the text tags: a browser is opaque to us rather than a
  // text field, and everything in the 3-pane sits inside one.
  const WHICHKEY_OPAQUE_TAGS = new Set(["browser"]);

  /**
   * @param {Element} el - element to check
   * @returns {boolean} true if the element or an ancestor takes typed text
   */
  tk.is_text_input = (el) => {
    for (let node = el; node; node = node.parentElement) {
      if (node.isContentEditable) return true;
      if (WHICHKEY_TEXT_TAGS.has(node.tagName?.toLowerCase?.() ?? ""))
        return true;
    }
    return false;
  };

  /**
   * @param {Element} el - event target to check
   * @returns {boolean} true if key events there should be left alone
   */
  tk.is_whichkey_text_target = (el) => {
    if (tk.is_text_input(el)) return true;
    for (let node = el; node; node = node.parentElement) {
      if (WHICHKEY_OPAQUE_TAGS.has(node.tagName?.toLowerCase?.() ?? ""))
        return true;
    }
    return false;
  };

  /**
   * @returns {boolean} true in the 3-pane mail window, false in compose windows
   */
  tk.is_mail_window = () =>
    window.document?.documentElement?.getAttribute("windowtype") ===
    "mail:3pane";

  const WHICHKEY_BG = "#0C0E13";
  const WHICHKEY_HEADER_COLOR = "#8A93A0";
  const WHICHKEY_KEY_COLOR = "#D8CF7F";
  const WHICHKEY_GROUP_COLOR = "#FFA0A0";
  const WHICHKEY_LABEL_COLOR = "#B0C8DE";

  /**
   * @returns {Element} the injected which-key panel, creating it if absent
   */
  tk.ensure_whichkey_panel = () => {
    const doc = window.document;
    let el = doc.getElementById("tbkeys-whichkey");
    if (el) return el;
    el = doc.createElement("div");
    el.id = "tbkeys-whichkey";
    el.style.cssText =
      "position:fixed; right:12px; bottom:32px; z-index:2147483647; " +
      `background:${WHICHKEY_BG}; border:1px solid #333; ` +
      "font:12px monospace; padding:6px 10px; " +
      "pointer-events:none; display:none;";
    (doc.body ?? doc.documentElement).appendChild(el);
    return el;
  };

  /**
   * @param {Document} doc - owner document to create the row in
   * @param {string} text - row text
   * @param {string} color - CSS color for the row
   * @returns {Element} a plain, single-color which-key row
   */
  tk.whichkey_text_row = (doc, text, color) => {
    const row = doc.createElement("div");
    row.textContent = text;
    row.style.color = color;
    return row;
  };

  /**
   * @param {Document} doc - owner document to create the row in
   * @param {string} key - key character(s), always colored WHICHKEY_KEY_COLOR
   * @param {string} label - description, colored `label_color`
   * @param {string} label_color - CSS color for the label half
   * @returns {Element} a which-key row with the key and label colored separately
   */
  tk.whichkey_entry_row = (doc, key, label, label_color) => {
    const row = doc.createElement("div");
    const key_span = doc.createElement("span");
    key_span.textContent = `  ${key}  `;
    key_span.style.color = WHICHKEY_KEY_COLOR;
    const label_span = doc.createElement("span");
    label_span.textContent = label;
    label_span.style.color = label_color;
    row.appendChild(key_span);
    row.appendChild(label_span);
    return row;
  };

  /**
   * Shows the next valid keys and labels under the current chord prefix;
   * a further chord leader is labeled like a "+group" entry, a plain
   * command like a regular label.
   * @param {string[]} path - keys pressed so far in this chord
   * @param {Object} children - trie children of the current node
   */
  tk.render_whichkey = (path, children) => {
    const el = tk.ensure_whichkey_panel();
    const doc = el.ownerDocument;
    el.textContent = "";
    el.appendChild(
      tk.whichkey_text_row(doc, path.join(" "), WHICHKEY_HEADER_COLOR),
    );
    for (const [key, node] of Object.entries(children)) {
      const is_group = !!node.children;
      const label = (is_group ? "+" : "") + (node.label ?? "...");
      el.appendChild(
        tk.whichkey_entry_row(
          doc,
          key,
          label,
          is_group ? WHICHKEY_GROUP_COLOR : WHICHKEY_LABEL_COLOR,
        ),
      );
    }
    el.style.display = "block";
  };

  /**
   * Shows every chord leader (as "+Label") and every single-key command,
   * for the "?" full command list.
   */
  tk.render_whichkey_full = () => {
    const el = tk.ensure_whichkey_panel();
    const doc = el.ownerDocument;
    el.textContent = "";
    el.appendChild(
      tk.whichkey_text_row(doc, "? -- all commands --", WHICHKEY_HEADER_COLOR),
    );
    for (const key of Object.keys(tk.whichkey_trie.children ?? {})) {
      el.appendChild(
        tk.whichkey_entry_row(
          doc,
          key,
          `+${tk.whichkey_group_labels[key] ?? "..."}`,
          WHICHKEY_GROUP_COLOR,
        ),
      );
    }
    for (const [key, label] of WHICHKEY_SINGLES) {
      el.appendChild(
        tk.whichkey_entry_row(doc, key, label, WHICHKEY_LABEL_COLOR),
      );
    }
    el.style.display = "block";
    tk.whichkey_full_shown = true;
  };

  /**
   * Hides the which-key panel and resets the chord walk back to the trie root.
   */
  tk.hide_whichkey = () => {
    const el = window.document.getElementById("tbkeys-whichkey");
    if (el) el.style.display = "none";
    if (tk.whichkey_timer) {
      window.clearTimeout(tk.whichkey_timer);
      tk.whichkey_timer = null;
    }
    tk.whichkey_node = tk.whichkey_trie;
    tk.whichkey_path = [];
    tk.whichkey_full_shown = false;
  };

  /**
   * Abandons a chord without running one: drops the read-state sample too, so a later chord cannot consume it. Completing a chord goes through hide_whichkey instead, leaving the sample for the action to restore from.
   */
  tk.abort_chord = () => {
    tk.read_snapshot = null;
    tk.suppress_keypress = null;
    tk.hide_whichkey();
  };

  /**
   * Capture-phase keydown observer that mirrors chord progress into the
   * which-key panel and suppresses a chord leader's native Thunderbird
   * shortcut. Never touches Mousetrap or tbkeys state it does not own.
   * @param {KeyboardEvent} e
   */
  tk.whichkey_handler = (e) => {
    tk.sync_insert_mode?.();
    if (
      e.ctrlKey ||
      e.altKey ||
      e.metaKey ||
      tk.is_whichkey_text_target(e.target)
    ) {
      if (tk.whichkey_node !== tk.whichkey_trie || tk.whichkey_full_shown)
        tk.abort_chord();
      return;
    }
    if (e.key === "Escape") {
      tk.abort_chord();
      return;
    }
    if (tk.whichkey_full_shown) {
      // Any key dismisses the full list rather than falling through to
      // chord tracking - it's a reference view, not a chord in progress.
      tk.abort_chord();
      return;
    }
    if (e.key === "?" && tk.whichkey_node === tk.whichkey_trie) {
      // No auto-hide timer - this is a reference list to read, dismissed
      // only by Esc or the next keypress (handled above).
      tk.render_whichkey_full();
      return;
    }
    const next = tk.whichkey_node.children?.[e.key];
    if (!next) {
      if (tk.whichkey_node !== tk.whichkey_trie || tk.whichkey_full_shown)
        tk.abort_chord();
      return;
    }
    tk.whichkey_path.push(e.key);
    tk.whichkey_node = next;
    tk.whichkey_full_shown = false;
    if (tk.whichkey_timer) window.clearTimeout(tk.whichkey_timer);
    if (next.children) {
      // Cancelling on keydown would take the keypress with it, and Mousetrap
      // needs that keypress to start a plain-character sequence.
      if (tk.is_mail_window()) {
        tk.suppress_keypress = e.key;
        // m is the only leader whose native shortcut writes read state, and
        // only an m chord ever restores, so a wider sample could only go stale.
        if (tk.whichkey_path.length === 1 && e.key === "m")
          tk.snapshot_read_state();
      }
      tk.render_whichkey(tk.whichkey_path, next.children);
      // Matches Mousetrap's own 1000ms sequence-reset delay so the overlay
      // never outlives the pending chord it is describing.
      tk.whichkey_timer = window.setTimeout(tk.abort_chord, 1000);
    } else {
      tk.hide_whichkey();
    }
  };

  /**
   * Cancels the native shortcut for a leader key that whichkey_handler has just seen open a chord. Runs on keypress so the event still reaches Mousetrap, which preventDefault does not block and which needs the keypress to start a plain-character sequence.
   * @param {KeyboardEvent} e
   */
  tk.whichkey_keypress_handler = (e) => {
    const key = tk.suppress_keypress;
    tk.suppress_keypress = null;
    if (key !== e.key || e.ctrlKey || e.altKey || e.metaKey) return;
    if (tk.is_whichkey_text_target(e.target)) return;
    e.preventDefault();
  };

  window.addEventListener("keydown", tk.whichkey_handler, { capture: true });
  window.addEventListener("keypress", tk.whichkey_keypress_handler, {
    capture: true,
  });

  tk.whichkey_teardown = () => {
    window.removeEventListener("keydown", tk.whichkey_handler, {
      capture: true,
    });
    window.removeEventListener("keypress", tk.whichkey_keypress_handler, {
      capture: true,
    });
    window.removeEventListener("unload", tk.whichkey_teardown);
    if (tk.whichkey_timer) window.clearTimeout(tk.whichkey_timer);
    window.document.getElementById("tbkeys-whichkey")?.remove();
  };
  window.addEventListener("unload", tk.whichkey_teardown, { once: true });

  tk.repaint_mode();
})(window.tk);
