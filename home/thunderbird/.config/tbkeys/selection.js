// Visual-mode state: window.vim/visualAnchor/visualEnd. Consumed directly by
// motions.js, navigation.js and actions.js rather than reimplemented per module.
(function (tk) {
  "use strict";

  /**
   * @returns {boolean} true when vim mode is "visual"
   */
  tk.is_visual = () => window.vim === "visual";

  // -- action target resolution ------------------------------------------

  /**
   * Resolves which messages a message action should target: the visual range when active, reasserting the tree selection to match it, or the current row repeated by count otherwise. Consumes any pending count prefix either way.
   * @param {Element} tt - the thread tree
   * @returns {{is_visual: boolean, count: number, anchor_hdr: (Object|undefined), top_index: (number|undefined), cursor_index: (number|undefined)}} - only is_visual and count are guaranteed; the rest are absent when there is no tree or no row to act on
   */
  tk.resolve_action_range = (tt) => {
    const is_visual = tk.is_visual();
    if (!is_visual) {
      const count = tk.peek_count();
      tk.reset_count();
      tk.effective_count = count;
      return {
        is_visual,
        count,
        anchor_hdr: tk.get_current_hdr(tt),
        top_index: tt?.currentIndex,
        cursor_index: tt?.currentIndex,
      };
    }
    tk.reset_count();
    tk.effective_count = 1;
    const last = (tt?.view?.rowCount ?? 0) - 1;
    const raw_anchor =
      typeof window.visualAnchor === "number"
        ? window.visualAnchor
        : tt?.currentIndex;
    const raw_end =
      typeof window.visualEnd === "number"
        ? window.visualEnd
        : tt?.currentIndex;
    // Anchor/end can outlive the rows they named when the view changed under
    // visual mode, so clamp before handing them to _selectRange.
    if (
      !tt ||
      last < 0 ||
      typeof raw_anchor !== "number" ||
      typeof raw_end !== "number"
    ) {
      return { is_visual, count: 1 };
    }
    const clamp = (i) => Math.min(Math.max(i, 0), last);
    const anchor = clamp(raw_anchor);
    const end = clamp(raw_end);
    tt._selectRange(anchor, end, false);
    return {
      is_visual,
      count: 1,
      anchor_hdr: tt.view?.getMsgHdrAt?.(anchor),
      top_index: Math.min(anchor, end),
      cursor_index: end,
    };
  };

  /**
   * Leaves visual mode and drops the recorded anchor/end without touching the tree selection, for a context change that makes those row indices meaningless.
   */
  tk.exit_visual = () => {
    window.vim = "normal";
    window.visualAnchor = undefined;
    window.visualEnd = undefined;
    tk.repaint_mode();
  };

  /**
   * Exits visual mode and collapses the tree selection to a single row after an action ran over a range.
   * @param {Element} tt - the thread tree
   * @param {number} cursor_index - row to select, clamped to the surviving row count
   */
  tk.finish_visual_action = (tt, cursor_index) => {
    window.vim = "normal";
    window.visualAnchor = undefined;
    window.visualEnd = undefined;
    const last = (tt?.view?.rowCount ?? 0) - 1;
    if (tt && last >= 0) {
      const target =
        typeof cursor_index === "number" && cursor_index >= 0
          ? cursor_index
          : last;
      tt._selectSingle(Math.min(target, last));
    }
    tk.repaint_mode();
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_toggle_visual = () => {
    const was_visual = window.vim === "visual";
    window.vim = was_visual ? "normal" : "visual";
    const tt = tk.get_thread_tree();
    if (!was_visual) {
      if (tt) {
        window.visualAnchor = tt.currentIndex;
        window.visualEnd = tt.currentIndex;
      }
    } else {
      window.visualAnchor = undefined;
      window.visualEnd = undefined;
    }
    tk.repaint_mode();
  };
})(window.tk);
