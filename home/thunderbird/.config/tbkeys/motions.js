// Vim-style h/j/k/l, gg/G, paging, viewport repositioning, and thread/folder
// fold commands. Motions resolve where an operation applies; actions.js owns
// the mutations.
(function (tk) {
  "use strict";

  // -- viewport repositioning -----------------------------------------------

  /**
   * Scrolls the tree so the current row lands at the given viewport position, without touching selection or currentIndex.
   * @param {Element} tt - the thread tree
   * @param {"top"|"center"|"bottom"} position - target position within the viewport
   */
  tk.reposition_row = (tt, position) => {
    const row_height = tt?._rowElementClass?.ROW_HEIGHT;
    if (!tt || typeof tt.currentIndex !== "number" || tt.currentIndex < 0)
      return;
    if (!row_height || typeof tt.scrollTo !== "function") return;
    const visible_height = tt.clientHeight;
    const top_of_row = row_height * tt.currentIndex;
    let target;
    if (position === "top") target = top_of_row;
    else if (position === "bottom")
      target = top_of_row + row_height - visible_height;
    else target = top_of_row + row_height / 2 - visible_height / 2;
    tt.scrollTo({ top: target, behavior: "instant" });
  };

  // -- flat tk_* functions for keys.json "func:" bindings ------------------

  window.tk_scroll_top = () => tk.reposition_row(tk.get_thread_tree(), "top");
  window.tk_scroll_center = () =>
    tk.reposition_row(tk.get_thread_tree(), "center");
  window.tk_scroll_bottom = () =>
    tk.reposition_row(tk.get_thread_tree(), "bottom");

  window.tk_collapse_all = () => {
    const e = tk.get_focused_element();
    if (!e) return;
    if (e.id === "threadTree") {
      window.goDoCommand("cmd_collapseAllThreads");
      return;
    }
    if (e.id === "folderTree") tk.collapse_folder_tree(e);
  };
  window.tk_expand_all = () => {
    const e = tk.get_focused_element();
    if (!e) return;
    if (e.id === "threadTree") {
      window.goDoCommand("cmd_expandAllThreads");
      return;
    }
    if (e.id === "folderTree") tk.expand_folder_tree(e);
  };

  window.tk_motion_left = () => {
    const inbox = tk.get_inbox_doc();
    if (!inbox) return window.CloseTabOrWindow();
    const is_visual = tk.is_visual();
    const n = tk.peek_count();
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        const v = e.view;
        let idx = e.currentIndex;
        if (v && !v.isContainer(idx)) {
          let parent = v.getParentIndex(idx);
          while (parent !== -1 && !v.isContainer(parent))
            parent = v.getParentIndex(parent);
          if (parent !== -1) {
            idx = parent;
            e._selectSingle(idx);
          }
        }
        if (v?.isContainer?.(idx) && v.isContainerOpen(idx))
          v.toggleOpenState(idx);
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < n; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowLeft",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_motion_right = () => {
    const inbox = tk.get_inbox_doc();
    if (!inbox) return window.goDoCommand("cmd_open");
    const is_visual = tk.is_visual();
    const count = tk.peek_count();
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        const idx = e.currentIndex;
        const v = e.view;
        if (v?.isContainer?.(idx) && !v.isContainerOpen(idx))
          v.toggleOpenState(idx);
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < count; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowRight",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_motion_down = () => {
    const inbox = tk.get_inbox_doc();
    const message = tk.get_message_content_window();
    if (!inbox && !message) return;
    const is_visual = tk.is_visual();
    const count = tk.peek_count();
    if (message) return message.scrollByLines(3);
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        if (is_visual) {
          const anchor =
            typeof window.visualAnchor === "number"
              ? window.visualAnchor
              : e.currentIndex;
          const cur =
            typeof window.visualEnd === "number"
              ? window.visualEnd
              : e.currentIndex;
          const last = (e.view?.rowCount ?? 1) - 1;
          const target = Math.min(cur + count, last);
          e._selectRange(anchor, target, false);
          window.visualEnd = target;
        } else {
          for (let i = 0; i < count; i++) window.goDoCommand("cmd_nextMsg");
        }
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < count; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowDown",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_motion_up = () => {
    const inbox = tk.get_inbox_doc();
    const message = tk.get_message_content_window();
    if (!inbox && !message) return;
    const is_visual = tk.is_visual();
    const count = tk.peek_count();
    if (message) return message.scrollByLines(-3);
    let e = inbox.activeElement;
    while (e) {
      if (e.id === "threadTree") {
        if (is_visual) {
          const anchor =
            typeof window.visualAnchor === "number"
              ? window.visualAnchor
              : e.currentIndex;
          const cur =
            typeof window.visualEnd === "number"
              ? window.visualEnd
              : e.currentIndex;
          const target = Math.max(cur - count, 0);
          e._selectRange(anchor, target, false);
          window.visualEnd = target;
        } else {
          for (let i = 0; i < count; i++) window.goDoCommand("cmd_previousMsg");
        }
        break;
      }
      if (e.id === "folderTree") {
        for (let i = 0; i < count; i++)
          e.handleEvent(
            new window.KeyboardEvent("keydown", {
              key: "ArrowUp",
              shiftKey: is_visual,
            }),
          );
        break;
      }
      e = e.parentElement;
    }
    tk.reset_count();
  };

  window.tk_page_up = () => {
    const e = tk.get_focused_element();
    if (e)
      e.handleEvent(new window.KeyboardEvent("keydown", { key: "PageUp" }));
  };
  window.tk_page_down = () => {
    const e = tk.get_focused_element();
    if (e)
      e.handleEvent(new window.KeyboardEvent("keydown", { key: "PageDown" }));
  };

  window.tk_goto_top = () => {
    const is_visual = tk.is_visual();
    const e = tk.get_focused_element();
    if (!e) return;
    const n = tk.peek_count();
    if (e.id === "threadTree") {
      const last = (e.view?.rowCount ?? 1) - 1;
      const target = Math.min(Math.max(n - 1, 0), Math.max(last, 0));
      if (is_visual) {
        const anchor =
          typeof window.visualAnchor === "number"
            ? window.visualAnchor
            : e.currentIndex;
        e._selectRange(anchor, target, false);
        window.visualEnd = target;
      } else {
        e._selectSingle(target);
      }
    } else if (e.id === "folderTree") {
      e.handleEvent(
        new window.KeyboardEvent("keydown", {
          key: "Home",
          shiftKey: is_visual,
        }),
      );
    }
    tk.reset_count();
  };

  window.tk_goto_bottom = () => {
    const is_visual = tk.is_visual();
    const e = tk.get_focused_element();
    if (!e) return;
    const has_count = tk.has_count();
    const n = tk.peek_count();
    if (e.id === "threadTree") {
      const last = (e.view?.rowCount ?? 1) - 1;
      const target = has_count
        ? Math.min(Math.max(n - 1, 0), Math.max(last, 0))
        : last;
      if (is_visual) {
        const anchor =
          typeof window.visualAnchor === "number"
            ? window.visualAnchor
            : e.currentIndex;
        e._selectRange(anchor, target, false);
        window.visualEnd = target;
      } else {
        e._selectSingle(target);
      }
    } else if (e.id === "folderTree") {
      e.handleEvent(
        new window.KeyboardEvent("keydown", {
          key: "End",
          shiftKey: is_visual,
        }),
      );
    }
    tk.reset_count();
  };
})(window.tk);
