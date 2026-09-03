// Incremental folder search: state, input, highlighting, matching,
// accept/cancel, and next/previous stepping. Owns tk_escape since most of its
// work is folder-search cleanup, reusing folders.js tree-shaping helpers.
(function (tk) {
  "use strict";

  tk.folder_search_active = false;
  tk.folder_search_origin_uri = null;
  tk.search_term = "";
  tk.active_search_kind = null;
  tk.thread_search = null;
  tk.message_search_active = false;

  const quick_filter_input = () =>
    tk.get_inbox_doc()?.getElementById("qfb-qs-textbox") ?? null;

  const emit_input = (input) => {
    input?.dispatchEvent(
      new input.ownerDocument.defaultView.Event("input", { bubbles: true }),
    );
    input?.dispatchEvent(
      new input.ownerDocument.defaultView.Event("change", { bubbles: true }),
    );
  };

  const replace_search_context = () => {
    if (tk.active_search_kind === "thread") tk.cancel_thread_search?.();
    if (tk.active_search_kind === "message") {
      window.goDoCommand("cmd_findClose");
      tk.message_search_active = false;
    }
    if (tk.folder_search_active || window.folderSearchMatches?.length) {
      const doc = tk.get_inbox_doc();
      doc?.getElementById("tbkeys-search-input")?.remove();
      if (doc) tk.clear_search_highlights?.(doc);
      tk.folder_search_active = false;
      tk.search_term = "";
      window.folderSearchMatches = undefined;
      window.folderSearchIndex = undefined;
      tk.folder_search_origin_uri = null;
    }
    tk.active_search_kind = null;
  };

  /**
   * Resolves the pane which owns the current focus. Message-pane focus is
   * represented by the browser in about:3pane, or by the content document
   * when focus has crossed into the displayed message.
   * @returns {"folder"|"thread"|"message"|null}
   */
  tk.focused_search_pane = () => {
    const focused = tk.get_focused_element();
    if (focused?.id === "folderTree") return "folder";
    if (focused?.id === "threadTree") return "thread";
    const about3pane = window.gTabmail?.currentAbout3Pane;
    const browser = window.gTabmail?.currentAboutMessage?.getMessagePaneBrowser?.();
    const active = about3pane?.document?.activeElement;
    if (browser && (active === browser || browser.contains?.(active)))
      return "message";
    if (browser?.contentDocument?.hasFocus?.()) return "message";
    return null;
  };

  tk.start_thread_search = () => {
    replace_search_context();
    const bar = window.gTabmail?.currentAbout3Pane?.quickFilterBar;
    if (!bar) {
      tk.show_status?.("SEARCH: Quick Filter Bar unavailable");
      return;
    }
    const was_hidden = bar.collapsed === true;
    bar._showFilterBar?.(true);
    const input = quick_filter_input();
    if (!input) {
      if (was_hidden) bar._showFilterBar?.(false);
      tk.show_status?.("SEARCH: Quick Filter input unavailable");
      return;
    }
    tk.thread_search = { input, original_value: input.value, was_hidden };
    const on_keydown = (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        window.tk_escape();
      } else if (event.key === "Enter") {
        event.preventDefault();
        event.stopPropagation();
        input.removeEventListener("keydown", on_keydown, true);
        tk.active_search_kind = "thread";
        input.blur();
        tk.repaint_mode();
      }
    };
    tk.thread_search.on_keydown = on_keydown;
    input.addEventListener("keydown", on_keydown, true);
    tk.active_search_kind = "thread";
    input.focus();
    input.select?.();
    input.value = "";
    emit_input(input);
    tk.repaint_mode();
  };

  tk.start_message_search = () => {
    replace_search_context();
    const browser = window.gTabmail?.currentAboutMessage?.getMessagePaneBrowser?.();
    if (!browser) {
      tk.show_status?.("SEARCH: message pane unavailable");
      return;
    }
    tk.active_search_kind = "message";
    tk.message_search_active = true;
    browser.focus?.();
    // cmd_find is Thunderbird's native find-in-message path. It owns the
    // find bar and therefore preserves the displayed message's find state.
    window.goDoCommand("cmd_find");
    tk.repaint_mode();
  };

  /**
   * @param {Document} fdoc - the folder tree's owner document
   */
  tk.ensure_search_style = (fdoc) => {
    if (fdoc.getElementById("tbkeys-search-style")) return;
    const style = fdoc.createElement("style");
    style.id = "tbkeys-search-style";
    style.textContent =
      ".tbkeys-search-match { background-color: #666666 !important; } " +
      ".tbkeys-search-active { background-color: #4D4528 !important; }";
    fdoc.head.appendChild(style);
  };

  /**
   * @param {Document} fdoc - the folder tree's owner document
   */
  tk.clear_search_highlights = (fdoc) => {
    fdoc
      .querySelectorAll(".tbkeys-search-match, .tbkeys-search-active")
      .forEach((el) =>
        el.classList.remove("tbkeys-search-match", "tbkeys-search-active"),
      );
  };

  /**
   * Scans the folder tree's current rows for name matches, highlights them, and selects the first one; used both while typing (tree left expanded) and after accept (tree recollapsed to matches).
   * @param {Element} ft - the folder tree
   * @param {string} term - search term, matched case-insensitively
   * @returns {number[]} row indices that matched
   */
  tk.apply_folder_search_highlight = (ft, term) => {
    const fdoc = ft.ownerDocument;
    tk.clear_search_highlights(fdoc);
    const t = term.toLowerCase();
    const matches = [];
    if (t) {
      for (let i = 0; i < ft.rowCount; i++) {
        const row = ft.getRowAtIndex(i);
        if (row?.nameLabel?.textContent?.toLowerCase().includes(t))
          matches.push(i);
      }
    }
    matches.forEach((i) =>
      ft.getRowAtIndex(i)?.classList.add("tbkeys-search-match"),
    );
    window.folderSearchMatches = matches;
    window.folderSearchIndex = 0;
    if (matches.length) {
      ft.getRowAtIndex(matches[0])?.classList.add("tbkeys-search-active");
      ft.selectedIndex = matches[0];
      ft.scrollToIndex?.(matches[0]);
    }
    return matches;
  };

  /**
   * @param {Element} ft - the folder tree
   * @returns {Element} the incremental-search text input, creating it above the folder tree if absent
   */
  tk.ensure_folder_search_input = (ft) => {
    const fdoc = ft.ownerDocument;
    let el = fdoc.getElementById("tbkeys-search-input");
    if (el) return el;
    el = fdoc.createElement("input");
    el.id = "tbkeys-search-input";
    el.type = "text";
    el.placeholder = "Search folders";
    el.style.cssText =
      "display:block; width:100%; box-sizing:border-box; font:inherit; " +
      "background:#222; color:#fff; border:1px solid #666; padding:2px 4px;";
    ft.parentElement?.insertBefore(el, ft);
    return el;
  };

  /**
   * @param {Element} ft - the folder tree
   */
  tk.close_folder_search_input = (ft) => {
    ft?.ownerDocument?.getElementById("tbkeys-search-input")?.remove();
  };

  /**
   * @param {Element} ft - the folder tree
   * @param {string} uri - folder URI to select, if a row for it is currently visible
   */
  tk.select_folder_row_by_uri = (ft, uri) => {
    for (let i = 0; i < ft.rowCount; i++) {
      if (ft.getRowAtIndex(i)?.uri === uri) {
        ft.selectedIndex = i;
        ft.scrollToIndex?.(i);
        return;
      }
    }
  };

  /**
   * Re-highlights matches for the term typed so far; the tree stays expanded so row indices don't shift per keystroke.
   * @param {Element} ft - the folder tree
   * @param {string} term - search term typed so far
   */
  tk.render_folder_search = (ft, term) => {
    tk.search_term = term.trim();
    tk.apply_folder_search_highlight(ft, tk.search_term);
    tk.repaint_mode();
  };

  /**
   * Opens the incremental folder search: expands the tree once (no per-keystroke collapse) and focuses a text input above it.
   */
  tk.start_folder_search = () => {
    replace_search_context();
    const ft = tk.get_folder_tree();
    if (!ft) return;
    const fdoc = ft.ownerDocument;
    tk.folder_search_origin_uri = ft.getRowAtIndex(ft.selectedIndex)?.uri ?? null;
    tk.ensure_search_style(fdoc);
    tk.clear_search_highlights(fdoc);
    tk.expand_folder_tree(ft);
    tk.folder_search_active = true;
    tk.active_search_kind = "folder";
    const input = tk.ensure_folder_search_input(ft);
    input.value = "";
    input.oninput = () => tk.render_folder_search(ft, input.value);
    input.onkeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        tk.accept_folder_search(ft);
      } else if (e.key === "Escape") {
        e.preventDefault();
        window.tk_escape();
      }
    };
    input.focus();
    tk.render_folder_search(ft, "");
  };

  /**
   * Accepts the typed term: recollapses the tree to just the matches and their ancestors, leaving highlighting in place for n/N. An empty term cancels instead, via tk_escape.
   * @param {Element} ft - the folder tree
   */
  tk.accept_folder_search = (ft) => {
    const term = tk.search_term.trim();
    if (!term) {
      window.tk_escape();
      return;
    }
    tk.close_folder_search_input(ft);
    tk.folder_search_active = false;
    const snapshot = tk.snapshot_folder_rows(ft);
    const t = term.toLowerCase();
    const match_idxs = [];
    snapshot.forEach((r, i) => {
      if (r.name.toLowerCase().includes(t)) match_idxs.push(i);
    });
    const keep = tk.keep_ancestors(snapshot, match_idxs);
    tk.collapse_folder_tree(ft, (row) => keep.has(row.uri));
    tk.apply_folder_search_highlight(ft, term);
    tk.repaint_mode();
    ft.focus();
  };

  /**
   * Steps the active folder search to the next/previous match; returns false when there is no active search so the caller can fall back to the built-in find command.
   * @param {number} direction - 1 for next, -1 for previous
   * @returns {boolean} true if a search step was taken
   */
  tk.folder_search_step = (direction) => {
    const focused = tk.get_focused_element();
    const matches = window.folderSearchMatches;
    if (focused?.id !== "folderTree" || !matches?.length) return false;
    const ft = tk.get_folder_tree();
    ft.getRowAtIndex(matches[window.folderSearchIndex])?.classList.remove(
      "tbkeys-search-active",
    );
    window.folderSearchIndex =
      (window.folderSearchIndex + direction + matches.length) % matches.length;
    const idx = matches[window.folderSearchIndex];
    ft.getRowAtIndex(idx)?.classList.add("tbkeys-search-active");
    ft.selectedIndex = idx;
    ft.scrollToIndex?.(idx);
    return true;
  };

  tk.search = () => {
    const pane = tk.focused_search_pane();
    if (pane === "folder") return tk.start_folder_search();
    if (pane === "thread") return tk.start_thread_search();
    if (pane === "message") return tk.start_message_search();
    tk.show_status?.("SEARCH: focus a folder, thread, or message pane");
  };

  tk.cancel_thread_search = () => {
    const session = tk.thread_search;
    if (!session) return false;
    session.input.removeEventListener("keydown", session.on_keydown, true);
    session.input.value = session.original_value;
    emit_input(session.input);
    if (session.was_hidden)
      window.gTabmail?.currentAbout3Pane?.quickFilterBar?._showFilterBar?.(false);
    tk.thread_search = null;
    tk.active_search_kind = null;
    tk.repaint_mode();
    return true;
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_escape = () => {
    if (tk.active_search_kind === "thread") {
      window.vim = "normal";
      window.count = 0;
      tk.cancel_thread_search();
      return;
    }
    if (tk.active_search_kind === "message") {
      window.vim = "normal";
      window.count = 0;
      window.goDoCommand("cmd_findClose");
      tk.message_search_active = false;
      tk.active_search_kind = null;
      tk.repaint_mode();
      return;
    }
    const was_visual = window.vim === "visual";
    window.vim = "normal";
    window.count = 0;
    tk.repaint_mode();
    if (was_visual) {
      const tt = tk.get_thread_tree();
      const end =
        typeof window.visualEnd === "number"
          ? window.visualEnd
          : tt?.currentIndex;
      if (tt && typeof end === "number") tt._selectSingle(end);
    }
    window.visualAnchor = undefined;
    window.visualEnd = undefined;
    const fdoc = window.gTabmail?.currentAbout3Pane?.document;
    const had_search =
      tk.folder_search_active ||
      !!(window.folderSearchMatches && window.folderSearchMatches.length);
    // True only when escape cancels a still-typing search - accepting one
    // commits its selection, so a later escape must not second-guess it.
    const cancelling_active_search = tk.folder_search_active;
    tk.folder_search_active = false;
    tk.search_term = "";
    if (fdoc) {
      fdoc.getElementById("tbkeys-search-input")?.remove();
      tk.clear_search_highlights(fdoc);
    }
    window.folderSearchMatches = undefined;
    window.folderSearchIndex = undefined;
    if (had_search) {
      const ft = tk.get_folder_tree();
      if (ft) {
        ft.focus();
        const sel_uri =
          cancelling_active_search && tk.folder_search_origin_uri
            ? tk.folder_search_origin_uri
            : ft.getRowAtIndex(ft.selectedIndex)?.uri;
        const snapshot = tk.snapshot_folder_rows(ft);
        const sel_idx = snapshot.findIndex((r) => r.uri === sel_uri);
        const keep = tk.keep_ancestors(
          snapshot,
          sel_idx !== -1 ? [sel_idx] : [],
        );
        tk.collapse_folder_tree(
          ft,
          (row) => keep.has(row.uri) || row.uri === sel_uri,
        );
        if (cancelling_active_search && sel_idx !== -1)
          tk.select_folder_row_by_uri(ft, sel_uri);
      }
    }
    tk.folder_search_origin_uri = null;
    if (had_search) tk.active_search_kind = null;
    tk.repaint_mode();
  };

  window.tk_search = () => tk.search();
  window.tk_folder_search = () => tk.start_folder_search();

  window.tk_search_next = () => {
    if (tk.folder_search_step(1)) return;
    if (tk.active_search_kind === "thread") return;
    if (
      tk.active_search_kind === "message" &&
      tk.focused_search_pane() === "message"
    )
      window.goDoCommand("cmd_findAgain");
  };
  window.tk_search_prev = () => {
    if (tk.folder_search_step(-1)) return;
    if (tk.active_search_kind === "thread") return;
    if (
      tk.active_search_kind === "message" &&
      tk.focused_search_pane() === "message"
    )
      window.goDoCommand("cmd_findPrevious");
  };
})(window.tk);
