// Visual-mode state: window.vim/visualAnchor/visualEnd. Consumed directly by
// motions.js, navigation.js and actions.js rather than reimplemented per module.
(function (tk) {
  "use strict";

  /**
   * @returns {boolean} true when vim mode is "visual"
   */
  tk.is_visual = () => window.vim === "visual";

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
