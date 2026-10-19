// The one file betterbird.cfg loads into each mail window. The module list
// lives here, next to the modules, so adding or renaming one never touches the
// system file, which only reaches /opt through install.sh or a Betterbird upgrade.
(function () {
  "use strict";

  // Dependency order: core/selection/folders come first so later modules can
  // rely on their primitives; whichkey loads last and fires the initial repaint.
  const MODULE_MANIFEST = [
    "core.js",
    "selection.js",
    "folders.js",
    "motions.js",
    "navigation.js",
    "actions.js",
    "yank.js",
    "editor.js",
    "search.js",
    "command.js",
    "ui.js",
    "hints.js",
    "whichkey.js",
  ];

  const tbkeys_file = (name) => {
    const file = Services.dirsvc.get("Home", Components.interfaces.nsIFile);
    file.append(".config");
    file.append("tbkeys");
    file.append(name);
    return file;
  };

  const load_file = (file, ignore_cache) =>
    Services.scriptloader.loadSubScriptWithOptions(
      Services.io.newFileURI(file).spec,
      { target: window, allowUnsafeURL: true, ignoreCache: ignore_cache },
    );

  /**
   * Loads every module into this window, or none if one is missing: core.js
   * replaces window.tk, so stopping before it would leave a half-built window.
   * @param {{ignore_cache?: boolean}} [options] - reread files edited since the last load
   * @returns {string|undefined} what went wrong, or undefined when all loaded
   */
  window.tbkeys_load_modules = ({ ignore_cache = false } = {}) => {
    const files = MODULE_MANIFEST.map(tbkeys_file);
    const missing = files.filter((file) => !file.exists()).map((file) => file.path);
    if (missing.length) return `tbkeys: not loaded, missing ${missing.join(", ")}`;

    for (const file of files) {
      try {
        load_file(file, ignore_cache);
      } catch (e) {
        return `tbkeys: ${file.path} failed to load, later modules skipped: ${e}`;
      }
    }
  };

  /**
   * Rereads this loader as well as the modules, so :reload picks up a changed
   * module list without a restart.
   * @returns {string|undefined} what went wrong, or undefined when all loaded
   */
  window.tbkeys_reload = () => {
    load_file(tbkeys_file("loader.js"), true);
    return window.tbkeys_load_modules({ ignore_cache: true });
  };
})();
