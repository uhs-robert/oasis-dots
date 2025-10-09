// menu.js
let _focusWindowsCache = null;
export default {
  "Hypr Windows": await getHyprWindows(), // executes on jiffy startup

  get "Hypr keybinds"() {
    return getHyprlandKeybinds(); // executes on menu access
  },

  get Binaries() {
    const result = [];
    const paths = STD.getenv("PATH")?.split(":");

    for (const path of paths) {
      const bins = OS.readdir(path)[0].filter(
        (name) => name !== "." && name !== "..",
      );
      for (const bin of bins) {
        result.push({
          name: bin,
          description: `Location: '${path}'`,
          exec: bin,
        });
      }
    }
    return result;
  },
};

async function getHyprWindows() {
  if (_focusWindowsCache) return _focusWindowsCache;
  const hyprState = JSON.parse(await execAsync(["hyprctl", "-j", "clients"]));
  _focusWindowsCache = hyprState.map((window) => ({
    name: window.class,
    description: window.title.replace("#", "_"),
    exec: `hyprctl dispatch focuswindow address:${window.address}`,
  }));
  return _focusWindowsCache;
}

let _hyprKeyBindsCache = null;
function getHyprlandKeybinds() {
  if (_hyprKeyBindsCache) return _hyprKeyBindsCache;
  const hyprBinds = JSON.parse(exec(["hyprctl", "-j", "binds"]));
  const mods = generateModMaskMap();
  _hyprKeyBindsCache = hyprBinds.map((keyBind) => ({
    name: `${(mods[keyBind.modmask] ?? [])
      .join(" + ")
      .concat(" ")}${keyBind.key}`,
    description: keyBind.description,
    exec: `${keyBind.dispatcher} ${keyBind.arg}`,
  }));
  return _hyprKeyBindsCache;

  function generateModMaskMap() {
    const modMaskMap = {};

    function parseModMask(modmask) {
      const modifiers = [];
      if (modmask & 1) modifiers.push("SHIFT");
      if (modmask & 4) modifiers.push("CTRL");
      if (modmask & 8) modifiers.push("ALT");
      if (modmask & 64) modifiers.push("SUPER");
      return modifiers;
    }

    const validModifiers = [1, 4, 8, 64];
    let validMasks = [0];

    for (const mod of validModifiers) {
      const newMasks = [];
      for (const mask of validMasks) {
        newMasks.push(mask | mod);
      }
      validMasks = [...validMasks, ...newMasks];
    }

    validMasks = validMasks.filter((mask) => mask !== 0);

    for (const mask of validMasks) {
      modMaskMap[mask] = parseModMask(mask).reverse();
    }

    return modMaskMap;
  }
}
