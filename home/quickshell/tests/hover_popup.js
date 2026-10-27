// Runs HoverPolicy.js under node: the hover-open state machine behind HoverPopup. The tests play the timers by hand,
// firing each event the way the QML helper would, so the lifecycle races are checked without a compositor.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPolicy.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { inside_changed, open_elapsed, close_elapsed, clicked, popup_changed, nothing_open_now, popup_pressed, disabled, open_here, swap_ok, swap_source };", T);
const P = T.api;

// A model of the world around the helper: the pointer, which popup is open, and the two timers.
function world() {
  const w = { mode: "idle", module: false, popup: false, open_name: "", open_timer: false, close_timer: false, opened: 0, closed: 0 };
  w.inside = () => w.module || (w.popup && w.open_name === "media");
  w.apply = r => {
    w.mode = r.mode;
    if (r.open_timer === "start") w.open_timer = true;
    if (r.open_timer === "stop") w.open_timer = false;
    if (r.close_timer === "start") w.close_timer = true;
    if (r.close_timer === "stop") w.close_timer = false;
    if (r.action === "open") { w.set_open("media"); w.opened++; }
    if (r.action === "close" && w.open_name === "media") { w.set_open(""); w.closed++; }
  };
  w.set_open = name => {
    const before = w.open_name === "media";
    w.open_name = name;
    if (name === "") w.popup = false;
    if ((name === "media") !== before) w.apply(P.popup_changed(w.mode, name === "media", w.inside()));
  };
  w.pointer = (module, popup) => {
    const before = w.inside();
    w.module = module;
    w.popup = popup && w.open_name === "media";
    if (w.inside() !== before) w.apply(P.inside_changed(w.mode, w.inside(), w.open_name === ""));
  };
  w.fire_open = () => { if (w.open_timer) { w.open_timer = false; w.apply(P.open_elapsed(w.mode, w.inside(), w.open_name === "")); } };
  w.fire_close = () => { if (w.close_timer) { w.close_timer = false; w.apply(P.close_elapsed(w.mode, w.inside())); } };
  w.click = () => w.apply(P.clicked(w.mode, w.open_name === "media"));
  return w;
}

const cases = [];
const t = (name, fn) => cases.push([name, fn]);

t("hover long enough opens, leaving closes after the grace", () => {
  const w = world();
  w.pointer(true, false);
  assert.strictEqual(w.mode, "pending");
  w.fire_open();
  assert.deepStrictEqual([w.mode, w.open_name], ["hover_open", "media"]);
  w.pointer(false, false);
  assert.strictEqual(w.open_name, "media");
  w.fire_close();
  assert.deepStrictEqual([w.mode, w.open_name, w.closed], ["idle", "", 1]);
});

t("module to popup and back never closes", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  for (let i = 0; i < 5; i++) {
    w.pointer(false, false); // left the module, not yet on the popup
    assert.ok(w.close_timer);
    w.pointer(false, true); // on the popup
    assert.ok(!w.close_timer);
    w.fire_close();
    w.pointer(true, false); // back on the module
    w.fire_close();
  }
  assert.deepStrictEqual([w.mode, w.open_name, w.closed], ["hover_open", "media", 0]);
});

t("close timer firing in the same turn as a re-entry does not close", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  w.pointer(false, false);
  w.module = true; // re-entry whose event has not been processed yet
  w.fire_close();
  assert.strictEqual(w.open_name, "media");
});

t("rapid enter and leave before the delay never opens", () => {
  const w = world();
  for (let i = 0; i < 20; i++) { w.pointer(true, false); w.pointer(false, false); }
  assert.ok(!w.open_timer);
  w.fire_open();
  assert.deepStrictEqual([w.mode, w.open_name, w.opened], ["idle", "", 0]);
});

t("rapid enter and leave after the open leaves no stray popup", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  for (let i = 0; i < 20; i++) { w.pointer(false, false); w.pointer(true, false); }
  w.pointer(false, false);
  w.fire_close();
  assert.deepStrictEqual([w.mode, w.open_name, w.opened, w.closed], ["idle", "", 1, 1]);
});

t("a stale open timer after leaving does not open", () => {
  const w = world();
  w.pointer(true, false);
  w.module = false; // leave seen late: timer fires first
  w.fire_open();
  assert.deepStrictEqual([w.mode, w.open_name], ["idle", ""]);
});

t("click while hover-open pins; leaving then keeps it open", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  w.click();
  assert.strictEqual(w.mode, "pinned");
  w.pointer(false, false);
  w.fire_close();
  assert.deepStrictEqual([w.mode, w.open_name], ["pinned", "media"]);
});

t("click on a closed module opens it pinned; a second click closes", () => {
  const w = world();
  w.pointer(true, false);
  w.click();
  assert.deepStrictEqual([w.mode, w.open_name, w.open_timer], ["pinned", "media", false]);
  w.click();
  assert.deepStrictEqual([w.mode, w.open_name], ["suppressed", ""]);
});

t("an outside click (popup closed from outside) ends the pin and the module can open again", () => {
  const w = world();
  w.click();
  w.set_open("");
  assert.strictEqual(w.mode, "settling");
  w.fire_close();
  assert.strictEqual(w.mode, "idle");
  w.pointer(true, false);
  w.fire_open();
  assert.strictEqual(w.open_name, "media");
});

t("a pinned popup closed by a click on the module is not reopened by the hover still there", () => {
  const w = world();
  w.pointer(true, false);
  w.click();
  w.click(); // closes
  assert.deepStrictEqual([w.mode, w.open_name, w.open_timer], ["suppressed", "", false]);
  w.pointer(true, false);
  w.fire_open();
  assert.strictEqual(w.open_name, "");
  w.pointer(false, false);
  assert.strictEqual(w.mode, "idle");
  w.pointer(true, false);
  w.fire_open();
  assert.strictEqual(w.open_name, "media");
});

t("a click on the module that lands on the popup layer closes it without a hover reopen", () => {
  const w = world();
  w.set_open("media"); // pinned from outside
  w.pointer(false, false);
  w.set_open(""); // the outside_catch closes it; the module is not hovered at that moment
  assert.deepStrictEqual([w.mode, w.close_timer], ["settling", true]);
  w.pointer(true, false); // the bar gets the pointer back, unmoved
  assert.strictEqual(w.mode, "suppressed");
  w.fire_open();
  assert.strictEqual(w.open_name, "");
});

t("an outside click far from the module settles back to idle and hover works again", () => {
  const w = world();
  w.set_open("media");
  w.set_open("");
  assert.strictEqual(w.mode, "settling");
  w.fire_close();
  assert.strictEqual(w.mode, "idle");
  w.pointer(true, false);
  w.fire_open();
  assert.strictEqual(w.open_name, "media");
});

t("a press inside a hover-opened popup pins it; in any other mode it changes nothing", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  w.apply(P.popup_pressed(w.mode));
  assert.strictEqual(w.mode, "pinned");
  w.apply(P.popup_pressed(w.mode));
  assert.strictEqual(w.mode, "pinned");
  assert.strictEqual(P.popup_pressed("idle").mode, "idle");
});

t("another popup open: hover does not replace it", () => {
  const w = world();
  w.open_name = "clock";
  w.pointer(true, false);
  assert.strictEqual(w.mode, "idle");
  w.fire_open();
  assert.strictEqual(w.open_name, "clock");
});

t("a pending open is dropped when another popup opens first", () => {
  const w = world();
  w.pointer(true, false);
  w.open_name = "clock";
  w.fire_open();
  assert.deepStrictEqual([w.mode, w.open_name], ["idle", "clock"]);
});

t("opened from outside (IPC) counts as pinned and survives the pointer", () => {
  const w = world();
  w.set_open("media");
  assert.strictEqual(w.mode, "pinned");
  w.pointer(true, false);
  w.pointer(false, false);
  w.fire_close();
  assert.strictEqual(w.open_name, "media");
});

t("swapping to another popup resets the mode", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  w.set_open("clock");
  assert.deepStrictEqual([w.mode, w.open_timer, w.close_timer], ["idle", false, false]);
});

t("hiding the module closes a hover-open popup but not a pinned one", () => {
  const a = world();
  a.pointer(true, false);
  a.fire_open();
  a.apply(P.disabled(a.mode, a.open_name === "media"));
  assert.deepStrictEqual([a.mode, a.open_name], ["idle", ""]);
  const b = world();
  b.click();
  b.apply(P.disabled(b.mode, true));
  assert.deepStrictEqual([b.mode, b.open_name], ["pinned", "media"]);
});

t("no timer is left running once idle", () => {
  const w = world();
  w.pointer(true, false);
  w.fire_open();
  w.pointer(false, false);
  w.fire_close();
  assert.deepStrictEqual([w.open_timer, w.close_timer], [false, false]);
});

t("another monitor's popup of the same name is not this module's own", () => {
  assert.strictEqual(P.open_here("media", "DP-1", "media", "DP-1"), true);
  assert.strictEqual(P.open_here("media", "DP-2", "media", "DP-1"), false);
  assert.strictEqual(P.open_here("clock", "DP-1", "media", "DP-1"), false);
  assert.strictEqual(P.open_here("media", "DP-2", "media", ""), true, "a module with no screen name matches any");
});

t("disabled while pending (nothing to show) drops the open and never opens", () => {
  const w = world();
  w.pointer(true, false);
  w.apply(P.disabled(w.mode, w.open_name === "media"));
  assert.deepStrictEqual([w.mode, w.open_timer], ["idle", false]);
  w.fire_open();
  assert.strictEqual(w.open_name, "");
});

// The QML wiring has no compositor test, so pin which modules opt in and how the base routes a click.
const bar_dir = path.join(__dirname, "../.config/quickshell/features/bar/modules");
const module_source = name => fs.readFileSync(path.join(bar_dir, name + ".qml"), "utf8");
t("the click-to-open modules and Media opt in; Start and Tray do not", () => {
  for (const m of ["Battery", "Bluetooth", "Network", "Volume", "Updates", "System", "Weather", "Keeptabs", "Notifications", "Media"]) {
    assert.match(module_source(m), /^\s+hover_popup: true$/m, m);
  }
  for (const m of ["StartButton", "Tray"]) assert.doesNotMatch(module_source(m), /hover_popup: true/, m);
});
t("Notifications hover-opens only with notifications", () => {
  assert.match(module_source("Notifications"), /hover_ready: NotificationState\.history\.length > 0/);
});
t("the base routes toggle_popup through the helper and drops the tooltip when hover opens", () => {
  const base = module_source("BarModule");
  assert.match(base, /if \(root\.hover_active\) hover\.click\(\);/);
  assert.match(base, /hover_handler\.hovered && !root\.hover_active\) Tooltip\.show/);
  assert.match(base, /onHover_activeChanged: root\.sync_tooltip\(\)/);
  assert.doesNotMatch(base, /hover_popups/);
});

t("pointer arrives while another popup is open: the open starts once nothing is open", () => {
  const w = world();
  w.open_name = "other";
  w.pointer(true, false);
  assert.deepStrictEqual([w.mode, w.open_timer], ["idle", false]);
  w.open_name = "";
  w.apply(P.nothing_open_now(w.mode, w.inside()));
  assert.strictEqual(w.mode, "pending");
  w.fire_open();
  assert.deepStrictEqual([w.mode, w.open_name], ["hover_open", "media"]);
});
t("nothing_open_now changes nothing outside idle-and-inside", () => {
  for (const m of ["pending", "hover_open", "pinned", "suppressed", "settling"]) assert.strictEqual(P.nothing_open_now(m, true).mode, m);
  assert.strictEqual(P.nothing_open_now("idle", false).mode, "idle");
});
t("HoverPopup reacts to nothing_open", () => {
  const src = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPopup.qml"), "utf8");
  assert.match(src, /onNothing_openChanged: if \(root\.enabled && root\.nothing_open\)/);
});

t("same-name modules: only the hover-opening helper reads the popup as its own", () => {
  const src = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPopup.qml"), "utf8");
  assert.match(src, /&& \(!Popups\.hover_owner \|\| Popups\.hover_owner === root\)/);
  assert.match(src, /if \(r\.mode === "hover_open"\) Popups\.hover_owner = root;\n\s+Popups\.open\(/);
  assert.match(src, /if \(r\.mode === "pinned" && r\.action !== "open"\) Popups\.hover_owner = null;/);
});
t("the open popup never shows without its owner: the owner clears after open_name moves", () => {
  const hover_popup = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPopup.qml"), "utf8");
  assert.match(hover_popup, /Popups\.open\([^\n]*\);\n\s+if \(r\.mode !== "hover_open"\) Popups\.hover_owner = null;/);
  const close = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/Popups.qml"), "utf8").match(/function close\(\) \{[^}]*\}/)[0];
  assert.ok(close.indexOf('open_name = "";') >= 0 && close.indexOf('open_name = "";') < close.indexOf("hover_owner = null;"), close);
});
t("hover over a popup's controls counts: a HoverHandler inside reveal also feeds set_popup_hover", () => {
  const popup = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/frames/Popup.qml"), "utf8");
  const reveal = popup.slice(popup.indexOf("id: reveal"));
  assert.match(reveal.slice(0, reveal.indexOf("StyledFrame {")), /HoverHandler \{\n\s+id: content_hover\n\s+enabled: !root\.passive\n\s+onHoveredChanged: root\.report_hover\(\)/);
  // A closing popup may only clear its own name: reveal shrinks under a still pointer as it animates out.
  assert.match(popup, /Popups\.set_popup_hover\(root\.popup_name, root\.wanted && \(panel_hover\.hovered \|\| content_hover\.hovered\)\)/);
  // ...and a popup wanted again mid-close, under a pointer that never moved, reports itself.
  assert.match(popup, /onWantedChanged: \{[\s\S]*?\} else if \(wanted\) \{[^}]*root\.report_hover\(\);/);
  assert.match(popup, /id: panel_hover\n\s+enabled: !root\.passive\n\s+onHoveredChanged: root\.report_hover\(\)/);
});
t("Media uses the base helper: no private HoverPopup, and a click goes through toggle_popup", () => {
  const media = module_source("Media");
  assert.doesNotMatch(media, /HoverPopup/);
  assert.doesNotMatch(media, /hover_popup\.click/);
  assert.match(media, /else root\.toggle_popup\(\);/);
});
t("a popup-less module (the legacy cava alias) never toggles an unregistered popup name", () => {
  assert.match(module_source("Cava"), /has_popup: false/);
  assert.match(module_source("BarModule"), /function toggle_popup\(\) \{\n\s+if \(!root\.has_popup\) return;/);
});
t("the hover switch and the per-module helper pointer are gone", () => {
  const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
  const quickshell_tree = path.join(__dirname, "../.config/quickshell");
  for (const f of walk(quickshell_tree).filter(f => /\.(qml|js)$/.test(f))) {
    const src = fs.readFileSync(f, "utf8");
    assert.doesNotMatch(src, /hover_popups/, f);
    assert.doesNotMatch(src, /popup_helper/, f);
  }
});

// Piece B: two adjacent hover zones (two lualine cells, or a cell and the clock) each own a helper over the one shared
// popup slot. The model plays the QML wiring: a helper's "inside" is its own zone or (its popup is open and the pointer
// is on the popup), and every helper hears nothing_open when the slot empties.
function pair() {
  const names = ["a", "b"];
  const h = { open_name: "", popup: false, pointer: null, opened: [], helpers: {} };
  for (const n of names) h.helpers[n] = { mode: "idle", open_timer: false, close_timer: false };
  const inside = n => h.pointer === n || (h.popup && h.open_name === n);
  const apply = (n, r) => {
    const x = h.helpers[n];
    x.mode = r.mode;
    if (r.open_timer === "start") x.open_timer = true;
    if (r.open_timer === "stop") x.open_timer = false;
    if (r.close_timer === "start") x.close_timer = true;
    if (r.close_timer === "stop") x.close_timer = false;
    if (r.action === "open") set_open(n);
    if (r.action === "close" && h.open_name === n) set_open("");
  };
  const set_open = name => {
    const before = h.open_name;
    h.open_name = name;
    if (name === "") h.popup = false;
    if (name !== "") h.opened.push(name);
    for (const n of names) {
      if ((before === n) !== (name === n)) apply(n, P.popup_changed(h.helpers[n].mode, name === n, inside(n)));
      if (name === "") apply(n, P.nothing_open_now(h.helpers[n].mode, inside(n)));
    }
  };
  h.move = (zone, on_popup) => {
    const before = Object.fromEntries(names.map(n => [n, inside(n)]));
    h.pointer = zone;
    h.popup = !!on_popup && h.open_name !== "";
    for (const n of names) if (inside(n) !== before[n]) apply(n, P.inside_changed(h.helpers[n].mode, inside(n), h.open_name === ""));
  };
  h.open_fire = n => { const x = h.helpers[n]; if (x.open_timer) { x.open_timer = false; apply(n, P.open_elapsed(x.mode, inside(n), h.open_name === "")); } };
  h.close_fire = n => { const x = h.helpers[n]; if (x.close_timer) { x.close_timer = false; apply(n, P.close_elapsed(x.mode, inside(n))); } };
  h.click = n => apply(n, P.clicked(h.helpers[n].mode, h.open_name === n));
  return h;
}

t("the gap between a zone and its popup stays open inside the 250 ms grace", () => {
  const h = pair();
  h.move("a");
  h.open_fire("a");
  h.move(null); // in the gap: on neither the zone nor the popup
  assert.ok(h.helpers.a.close_timer);
  h.move(null, true); // reaches the popup before the grace runs out
  assert.ok(!h.helpers.a.close_timer);
  h.close_fire("a");
  assert.deepStrictEqual([h.helpers.a.mode, h.open_name], ["hover_open", "a"]);
  h.move(null);
  h.close_fire("a"); // the grace runs out with the pointer away
  assert.strictEqual(h.open_name, "");
});

t("sweeping from one zone to its neighbour hands over once, with no stuck or double popup", () => {
  const h = pair();
  h.move("a");
  h.open_fire("a");
  h.move("b"); // adjacent zones: no gap, a leaves and b enters at once
  assert.deepStrictEqual([h.open_name, h.helpers.b.mode], ["a", "idle"]);
  assert.ok(!h.helpers.b.open_timer, "b waits for the slot to empty");
  h.close_fire("a");
  assert.strictEqual(h.open_name, "");
  assert.strictEqual(h.helpers.b.mode, "pending");
  h.open_fire("b");
  assert.deepStrictEqual([h.open_name, h.helpers.a.mode, h.helpers.b.mode, h.opened], ["b", "idle", "hover_open", ["a", "b"]]);
});

t("a quick pass over a neighbour opens nothing and leaves the first popup to close", () => {
  const h = pair();
  h.move("a");
  h.open_fire("a");
  h.move("b");
  h.move("a"); // back before a's grace ends
  h.close_fire("a");
  assert.deepStrictEqual([h.open_name, h.helpers.a.mode, h.helpers.b.mode], ["a", "hover_open", "idle"]);
  h.move(null);
  h.close_fire("a");
  assert.deepStrictEqual([h.open_name, h.helpers.b.open_timer, h.helpers.b.close_timer], ["", false, false]);
});

t("a click on a neighbour while the first is hover-open does not open a second popup or leave one stuck", () => {
  const h = pair();
  h.move("a");
  h.open_fire("a");
  h.move("b");
  h.close_fire("a");
  h.click("b"); // b's pending open is replaced by a pin
  assert.deepStrictEqual([h.open_name, h.helpers.b.mode], ["b", "pinned"]);
  h.move(null);
  h.close_fire("b");
  assert.strictEqual(h.open_name, "b");
});

t("a click in a zone's lead or padding while hover-open pins; the next click closes without a reopen", () => {
  const h = pair();
  h.move("a");
  h.open_fire("a");
  h.click("a");
  assert.strictEqual(h.helpers.a.mode, "pinned");
  h.move(null);
  h.close_fire("a");
  assert.strictEqual(h.open_name, "a");
  h.move("a");
  h.click("a");
  assert.deepStrictEqual([h.open_name, h.helpers.a.mode], ["", "suppressed"]);
  h.open_fire("a");
  assert.strictEqual(h.open_name, "");
});

// The QML wiring for piece B.
const bar_root = path.join(__dirname, "../.config/quickshell/features/bar");
const bar_source = rel => fs.readFileSync(path.join(bar_root, rel), "utf8");
t("a lualine cell lends its whole hover zone to the module and routes its click through the module", () => {
  const cell = bar_source("neovim/LualineSection.qml");
  assert.match(cell, /item\.cell_hovered = Qt\.binding\(\(\) => cell_hover\.hovered\)/);
  assert.match(cell, /if \(it\.toggle_popup\) it\.toggle_popup\(\);\n\s+else if \(it\.click_popup\) it\.click_popup\(\);/);
  assert.match(module_source("BarModule"), /readonly property bool hovered: hover_handler\.hovered \|\| root\.cell_hovered/);
});
t("the clock opens its popup on hover over the entry and pins on every click path", () => {
  const clock = module_source("Clock");
  assert.match(clock, /HoverPopup \{\n\s+id: hover_popup\n\s+popup_name: "clock"/);
  assert.match(clock, /onTapped: root\.click_popup\(\)/);
  assert.match(clock, /if \(root\.hover_active\) hover_popup\.click\(\);/);
  assert.match(clock, /!root\.hover_active\) Tooltip\.show/);
  const bar = bar_source("Bar.qml");
  assert.doesNotMatch(bar, /Popups\.toggle\("clock"/);
  assert.strictEqual((bar.match(/root\.clock_item && root\.clock_item\.click_popup\(\)/g) || []).length, 3);
});
t("the lualine cava slot hovers and pins the media popup, and only while shown", () => {
  const strip = bar_source("neovim/LualineStrip.qml");
  assert.match(strip, /HoverPopup \{\n\s+id: slot_popup\n\s+popup_name: "media"\n\s+module: cava_slot\n\s+enabled: cava_slot\.shown/);
  assert.match(strip, /onClicked: \{\n\s+slot_popup\.click\(\);/);
});

// Two helpers on one popup name (the lualine cava slot "s" and the Media module "m") around a Popups model. Each helper
// reacts when its own open_here or nothing_open flips, after every single assignment, as the QML bindings do. `rule` is
// how a helper reacts to losing the owner: "shared" is 755c90cbc's handler in every helper, immediate; "slot" is the
// slot's deferred look; "none" is neither. `order` is when hover_owner clears around open_name: "fixed" after it (close()
// and a pinned open today), "old" before it, which showed the popup ownerless for one assignment.
// D: a third helper "n" (the neighbouring Network module, its own popup) lets the pointer move between modules while a
// popup is hover-open, which HoverPopup turns into a swap ("swap" action) after a short delay. `closes` counts
// Popups.close() calls and `ownerless` records any helper seeing an open popup with no owner during a swap. `islands`
// is each helper's island; by default the lualine bar's: Media on the left island, the cava slot and Network on the right.
function twins(rule, order = "fixed", islands = { s: "right", m: "left", n: "right" }) {
  const fresh = () => ({ mode: "idle", open_timer: false, close_timer: false, saw_open: false, saw_nothing: true });
  const names = { s: "media", m: "media", n: "network" };
  const w = { open_name: "", anchor: null, owner: null, pointer: null, queued: false, closes: 0, name_moves: 0, ownerless: [], in_swap: false, h: { s: fresh(), m: fresh(), n: fresh() } };
  const open_here = n => w.open_name === names[n] && (!w.owner || w.owner === n);
  const inside = n => w.pointer === n;
  // HoverPopup.other_hover_open, on one screen: a same-name sibling's popup only from the same island.
  const other_hover_open = n => !!w.owner && w.owner !== n && w.h[w.owner].mode === "hover_open" && open_here(w.owner)
    && (w.open_name !== names[n] || w.anchor === islands[n]);
  w.other_hover_open = other_hover_open;
  const notify = () => {
    if (w.in_swap && w.open_name !== "" && !w.owner) w.ownerless.push(w.open_name);
    for (const n of ["s", "m", "n"]) {
      const x = w.h[n];
      if (x.saw_open !== open_here(n)) { x.saw_open = open_here(n); apply(n, P.popup_changed(x.mode, x.saw_open, inside(n))); }
      if (x.saw_nothing !== (w.open_name === "")) { x.saw_nothing = w.open_name === ""; if (x.saw_nothing) apply(n, P.nothing_open_now(x.mode, inside(n))); }
    }
  };
  const apply = (n, r) => {
    const x = w.h[n];
    x.mode = r.mode;
    if (r.open_timer === "start") x.open_timer = true;
    if (r.open_timer === "stop") x.open_timer = false;
    if (r.close_timer === "start") x.close_timer = true;
    if (r.close_timer === "stop") x.close_timer = false;
    if (r.mode === "pinned" && (order === "old" || r.action !== "open")) set_owner(null);
    if (r.action === "open") {
      if (order === "old") set_owner(r.mode === "hover_open" ? n : null);
      else if (r.mode === "hover_open") set_owner(n);
      open_at(n);
      if (order !== "old" && r.mode !== "hover_open") set_owner(null);
    }
    else if (r.action === "swap") {
      // HoverPopup's swap: the new owner first, then open_name moves (or, from a same-name sibling, stays).
      w.in_swap = true;
      if (order === "old") set_owner(null);
      set_owner(n);
      if (w.open_name !== names[n]) open_at(n);
      w.in_swap = false;
    }
    else if (r.action === "close" && open_here(n)) close();
  };
  const set_owner = o => {
    if (w.owner === o) return;
    w.owner = o;
    if (rule === "shared") for (const n of ["s", "m"]) if (w.h[n].mode === "hover_open" && w.owner !== n && open_here(n)) apply(n, P.popup_pressed(w.h[n].mode));
    if (rule === "slot" && w.h.s.mode === "hover_open") w.queued = true;
    notify();
  };
  // Popups.open from helper n: anchored to its island; open_name moving last, as in Popups.open.
  const open_at = n => { w.anchor = islands[n]; set_name(names[n]); };
  const set_name = name => {
    if (w.open_name === name) return;
    w.open_name = name;
    w.name_moves++;
    notify();
  };
  const close = () => {
    w.closes++;
    if (order === "old") set_owner(null);
    set_name("");
    w.anchor = null;
    set_owner(null);
  };
  // Qt.callLater: runs once the call that changed the owner has finished.
  const settle = () => {
    if (!w.queued) return;
    w.queued = false;
    if (w.h.s.mode === "hover_open" && !w.owner && open_here("s")) apply("s", P.popup_pressed("hover_open"));
  };
  w.hover_open = n => { w.pointer = n; apply(n, P.inside_changed("idle", true, true)); w.fire_open(n); };
  w.move = n => {
    const was = w.pointer;
    w.pointer = n;
    if (was) apply(was, P.inside_changed(w.h[was].mode, false, w.open_name === "", other_hover_open(was)));
    if (n) apply(n, P.inside_changed(w.h[n].mode, true, w.open_name === "", other_hover_open(n)));
    settle();
  };
  w.click = n => {
    apply(n, P.clicked(w.h[n].mode, open_here(n)));
    // The slot's click handler tells every helper on its popup name, like a press inside the popup.
    if (rule === "slot" && n === "s") for (const o of ["s", "m"]) apply(o, P.popup_pressed(w.h[o].mode));
    settle();
  };
  w.fire_open = n => { const x = w.h[n]; if (x.open_timer) { x.open_timer = false; apply(n, P.open_elapsed(x.mode, inside(n), w.open_name === "", other_hover_open(n))); settle(); } };
  w.fire_close = n => { const x = w.h[n]; if (x.close_timer) { x.close_timer = false; apply(n, P.close_elapsed(x.mode, inside(n))); settle(); } };
  // Escape, an outside click and a toggle all end in Popups.close().
  w.close_from_outside = () => { close(); settle(); };
  // A keybind or IPC open (Popups.open_with_keyboard, open_on): open_name moves, the owner is left alone.
  w.open_from_key = name => { set_name(name); settle(); };
  // A click-open of another popup by its own helper: a pinned open, so the owner clears around the open_name move.
  w.open_other = () => {
    if (order === "old") set_owner(null);
    set_name("other");
    set_owner(null);
    settle();
  };
  return w;
}
const media_open_and_pinned = w => [w.open_name, w.h.s.mode, w.h.m.mode];
t("a click on the Media module pins the popup the cava slot hover-opened; the slot's close grace does not shut it", () => {
  const w = twins("slot");
  w.hover_open("s");
  w.move("m");
  w.click("m");
  w.fire_close("s");
  assert.deepStrictEqual(media_open_and_pinned(w), ["media", "pinned", "pinned"]);
});
t("without any hand-over the slot's grace closes the pinned popup (the bug)", () => {
  const w = twins("none");
  w.hover_open("s");
  w.move("m");
  w.click("m");
  w.fire_close("s");
  assert.strictEqual(w.open_name, "");
});
t("a click on the cava slot pins the popup the Media module hover-opened; Media's close grace does not shut it", () => {
  const w = twins("slot");
  w.hover_open("m");
  w.move("s");
  w.click("s");
  w.fire_close("m");
  assert.deepStrictEqual(media_open_and_pinned(w), ["media", "pinned", "pinned"]);
  const bug = twins("none");
  bug.hover_open("m");
  bug.move("s");
  bug.click("s");
  bug.fire_close("m");
  assert.strictEqual(bug.open_name, "");
});
t("a hover-opened popup closed from outside goes back to idle and hover-reopens at once", () => {
  {
    const w = twins("slot");
    w.hover_open("s");
    w.close_from_outside();
    assert.deepStrictEqual([w.open_name, w.h.s.mode], ["", "pending"]);
    w.fire_open("s");
    assert.deepStrictEqual([w.open_name, w.h.s.mode], ["media", "hover_open"]);
  }
});
t("a click-open of another popup does not pin the hover-opened one", () => {
  const w = twins("slot");
  w.hover_open("s");
  w.open_other();
  assert.strictEqual(w.h.s.mode, "idle");
});
// F (#1286): with the owner cleared before open_name, the instant between showed "media" open with no owner, and the
// idle sibling took it for an outside open and pinned, then went suppressed or settling as the popup closed.
const slot_after_media = order => {
  const w = twins("slot", order);
  w.hover_open("m");
  w.move("s");
  w.fire_close("m");
  return w;
};
t("the cava slot hover-opens the popup Media's grace just closed with the pointer already on the slot", () => {
  const w = slot_after_media("fixed");
  assert.deepStrictEqual([w.open_name, w.h.s.mode], ["", "pending"]);
  w.fire_open("s");
  assert.deepStrictEqual([w.open_name, w.h.s.mode, w.h.m.mode], ["media", "hover_open", "idle"]);
  assert.strictEqual(slot_after_media("old").h.s.mode, "suppressed");
});
const slot_after_gap = order => {
  const w = twins("slot", order);
  w.hover_open("m");
  w.move(null);
  w.fire_close("m");
  const after_close = w.h.s.mode;
  w.move("s");
  return [w, after_close];
};
t("the cava slot hover-opens after Media's popup closed with the pointer between them", () => {
  const [w, after_close] = slot_after_gap("fixed");
  assert.deepStrictEqual([after_close, w.h.s.mode], ["idle", "pending"]);
  w.fire_open("s");
  assert.deepStrictEqual([w.open_name, w.h.s.mode], ["media", "hover_open"]);
  const [bug, bug_after_close] = slot_after_gap("old");
  assert.deepStrictEqual([bug_after_close, bug.h.s.mode], ["settling", "suppressed"]);
});
t("Media hover-opens after the slot's popup closed, the reverse way", () => {
  const w = twins("slot");
  w.hover_open("s");
  w.move("m");
  w.fire_close("s");
  assert.strictEqual(w.h.m.mode, "pending");
  w.fire_open("m");
  assert.deepStrictEqual([w.open_name, w.h.m.mode], ["media", "hover_open"]);
});
t("an outside close of Media's hover-opened popup leaves the idle slot idle", () => {
  const close_media = order => { const w = twins("slot", order); w.hover_open("m"); w.close_from_outside(); return w; };
  assert.deepStrictEqual([close_media("fixed").h.s.mode, close_media("fixed").h.m.mode], ["idle", "pending"]);
  assert.strictEqual(close_media("old").h.s.mode, "settling");
});
t("a click-open of another popup leaves the idle sibling idle", () => {
  const open_other = order => { const w = twins("slot", order); w.hover_open("m"); w.open_other(); return w; };
  assert.deepStrictEqual([open_other("fixed").h.s.mode, open_other("fixed").h.m.mode], ["idle", "idle"]);
  assert.strictEqual(open_other("old").h.s.mode, "settling");
});
t("755c90cbc's shared handler pins on every close and on a click-open of another popup (why it was dropped)", () => {
  const closed = twins("shared", "old");
  closed.hover_open("s");
  closed.close_from_outside();
  assert.notStrictEqual(closed.h.s.mode, "pending");
  const other = twins("shared", "old");
  other.hover_open("s");
  other.open_other();
  assert.notStrictEqual(other.h.s.mode, "idle");
});
t("HoverPopup has no ownership handler; the slot alone watches it", () => {
  const src = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPopup.qml"), "utf8");
  assert.doesNotMatch(src, /hover_ownerChanged/);
  const strip = bar_source("neovim/LualineStrip.qml");
  assert.match(strip, /function onHover_ownerChanged\(\) \{\n\s+if \(slot_popup\.mode === "hover_open"\) Qt\.callLater\(cava_slot\.take_pin\);/);
  assert.match(strip, /!Popups\.hover_owner && slot_popup\.open_here\) Popups\.popup_pressed\(slot_popup\.popup_name\)/);
  assert.match(strip, /slot_popup\.click\(\);\n\s+\/\/[^\n]*\n\s+Popups\.popup_pressed\(slot_popup\.popup_name\);/);
  assert.match(strip, /enabled: cava_slot\.shown$/m);
});

// D (#1286): moving from one module onto the next while the first one's popup is hover-open swaps the popup in place.
t("swap_ok: only an idle module the pointer is on, and only from another module's hover-opened popup", () => {
  for (const m of ["idle", "pending", "swapping", "hover_open", "pinned", "suppressed", "settling"])
    for (const inside of [true, false])
      for (const other of [true, false]) assert.strictEqual(P.swap_ok(m, inside, other), m === "idle" && inside && other, [m, inside, other].join());
  assert.deepStrictEqual([P.inside_changed("idle", true, false, true).mode, P.inside_changed("idle", true, false, false).mode], ["swapping", "idle"]);
  assert.deepStrictEqual([P.inside_changed("swapping", false, false, true).mode, P.inside_changed("swapping", false, false, true).open_timer], ["idle", "stop"]);
  assert.deepStrictEqual([P.open_elapsed("swapping", true, false, true).action, P.open_elapsed("swapping", true, false, false).mode], ["swap", "idle"]);
  assert.strictEqual(P.nothing_open_now("swapping", true).mode, "pending");
  assert.strictEqual(P.popup_changed("swapping", true, true).mode, "pinned");
  assert.deepStrictEqual({ ...P.disabled("swapping", false) }, { mode: "idle", open_timer: "stop", close_timer: "stop", action: "none" });
});
t("swap_source: a swap only from another popup on the same screen, so never across monitors or bar edges", () => {
  assert.deepStrictEqual({ ...P.swap_source(true, "volume", "DP-1", "network", "DP-1") }, { name: "volume", to: "network", screen_name: "DP-1", extent: 0 });
  assert.strictEqual(P.swap_source(true, "volume", "DP-1", "network", "HDMI-A-1"), null);
  assert.strictEqual(P.swap_source(false, "volume", "DP-1", "network", "DP-1"), null);
  assert.strictEqual(P.swap_source(true, "", "", "network", "DP-1"), null);
  assert.strictEqual(P.swap_source(true, "network", "DP-1", "network", "DP-1"), null);
});
const swapped = (order = "fixed") => {
  const w = twins("slot", order);
  w.hover_open("m");
  w.move("n");
  const waiting = [w.h.n.mode, w.h.n.open_timer];
  w.fire_open("n");
  return [w, waiting];
};
t("a swap to the neighbour: the owner moves first, the old helper ends idle with no close() and never sees the popup ownerless", () => {
  const [w, waiting] = swapped();
  assert.deepStrictEqual(waiting, ["swapping", true]);
  assert.deepStrictEqual([w.open_name, w.owner, w.h.n.mode, w.h.m.mode, w.h.s.mode], ["network", "n", "hover_open", "idle", "idle"]);
  assert.deepStrictEqual([w.closes, w.ownerless, w.h.m.close_timer], [0, [], false]);
  // The old helper's grace was stopped; a stale fire finds nothing to do.
  w.fire_close("m");
  assert.deepStrictEqual([w.open_name, w.closes], ["network", 0]);
});
t("a pointer only crossing a module (shorter than the swap delay) does not swap", () => {
  const w = twins("slot");
  w.hover_open("m");
  w.move("n");
  w.move(null);
  w.fire_open("n");
  assert.deepStrictEqual([w.open_name, w.h.n.mode, w.h.n.open_timer], ["media", "idle", false]);
  w.fire_close("m");
  assert.deepStrictEqual([w.open_name, w.h.m.mode], ["", "idle"]);
});
t("fast moves: there and straight back keeps the first popup; a swap there and back swaps back", () => {
  const w = twins("slot");
  w.hover_open("m");
  w.move("n");
  w.move("m");
  w.fire_open("n");
  assert.deepStrictEqual([w.open_name, w.owner, w.h.m.mode, w.h.m.close_timer], ["media", "m", "hover_open", false]);
  const [back] = swapped();
  back.move("m");
  assert.strictEqual(back.h.m.mode, "swapping");
  back.fire_open("m");
  assert.deepStrictEqual([back.open_name, back.owner, back.h.m.mode, back.h.n.mode, back.closes, back.ownerless], ["media", "m", "hover_open", "idle", 0, []]);
});
t("no swap from a pinned popup", () => {
  const w = twins("slot");
  w.hover_open("m");
  w.click("m");
  w.move("n");
  w.fire_open("n");
  assert.deepStrictEqual([w.open_name, w.h.n.mode, w.h.m.mode], ["media", "idle", "pinned"]);
});
t("no swap from a popup a key or IPC opened, even with a stale owner left from an earlier hover", () => {
  const w = twins("slot");
  w.open_from_key("network");
  assert.deepStrictEqual([w.owner, w.h.n.mode], [null, "pinned"]);
  w.move("m");
  w.fire_open("m");
  assert.deepStrictEqual([w.open_name, w.h.m.mode], ["network", "idle"]);
  const stale = twins("slot");
  stale.hover_open("n");
  stale.open_from_key("media");
  assert.deepStrictEqual([stale.owner, stale.h.n.mode, stale.other_hover_open("m")], ["n", "idle", false]);
  stale.move("m");
  stale.fire_open("m");
  assert.deepStrictEqual([stale.open_name, stale.h.m.mode], ["media", "idle"]);
});
t("a swap waiting when the open popup closes falls back to the full open delay", () => {
  const w = twins("slot");
  w.hover_open("m");
  w.move("n");
  w.close_from_outside();
  assert.deepStrictEqual([w.open_name, w.h.n.mode, w.h.n.open_timer], ["", "pending", true]);
  w.fire_open("n");
  assert.deepStrictEqual([w.open_name, w.owner, w.h.n.mode], ["network", "n", "hover_open"]);
});
t("after a swap the new popup closes on leaving and the old module hover-reopens", () => {
  const [w] = swapped();
  w.move(null);
  w.fire_close("n");
  assert.deepStrictEqual([w.open_name, w.h.n.mode, w.closes], ["", "idle", 1]);
  w.move("m");
  assert.strictEqual(w.h.m.mode, "pending");
  w.fire_open("m");
  assert.deepStrictEqual([w.open_name, w.h.m.mode], ["media", "hover_open"]);
});
// Two same-name helpers on one island (system:cpu and system:memory).
const one_island = { s: "right", m: "right", n: "right" };
t("a same-name sibling on the same island swaps by handing the owner over; the popup stays and the sibling owns it", () => {
  const w = twins("slot", "fixed", one_island);
  w.hover_open("m");
  const moves = w.name_moves;
  w.move("s");
  w.fire_open("s");
  assert.deepStrictEqual([w.open_name, w.owner, w.h.s.mode, w.h.m.mode, w.name_moves - moves, w.closes, w.ownerless], ["media", "s", "hover_open", "idle", 0, 0, []]);
  w.fire_close("m");
  assert.strictEqual(w.open_name, "media");
  // ...and back.
  w.move("m");
  w.fire_open("m");
  assert.deepStrictEqual([w.owner, w.h.m.mode, w.h.s.mode], ["m", "hover_open", "idle"]);
});
t("Media to the cava slot (different islands) does not swap: the popup stays on Media's island, closes after the grace and the slot reopens it", () => {
  const w = twins("slot");
  w.hover_open("m");
  w.move("s");
  assert.deepStrictEqual([w.h.s.mode, w.h.s.open_timer, w.other_hover_open("s")], ["idle", false, false]);
  w.fire_open("s");
  assert.deepStrictEqual([w.open_name, w.owner, w.anchor], ["media", "m", "left"]);
  w.fire_close("m");
  assert.deepStrictEqual([w.open_name, w.h.s.mode, w.h.s.open_timer], ["", "pending", true]);
  w.fire_open("s");
  assert.deepStrictEqual([w.open_name, w.owner, w.anchor, w.h.s.mode, w.h.m.mode], ["media", "s", "right", "hover_open", "idle"]);
});
t("the cava slot swapping away to another module ends idle and the slot's owner watch does not pin", () => {
  const w = twins("slot");
  w.hover_open("s");
  w.move("n");
  w.fire_open("n");
  assert.deepStrictEqual([w.open_name, w.h.s.mode, w.h.n.mode, w.queued], ["network", "idle", "hover_open", false]);
});
t("the cava/Media pin races still hold with a swap pending or done", () => {
  // A click on the slot inside its swap delay: a pinned open of the same name; Media's grace must not close it.
  const a = twins("slot");
  a.hover_open("m");
  a.move("s");
  a.click("s");
  a.fire_close("m");
  assert.deepStrictEqual(media_open_and_pinned(a), ["media", "pinned", "pinned"]);
  // A click on Media inside its swap delay from the slot's popup: the slot's owner watch takes the pin.
  const b = twins("slot");
  b.hover_open("s");
  b.move("m");
  b.click("m");
  b.fire_close("s");
  assert.deepStrictEqual(media_open_and_pinned(b), ["media", "pinned", "pinned"]);
  // After a finished hand-over (same island) the click pins both.
  const c = twins("slot", "fixed", one_island);
  c.hover_open("m");
  c.move("s");
  c.fire_open("s");
  c.click("s");
  c.fire_close("m");
  assert.deepStrictEqual(media_open_and_pinned(c), ["media", "pinned", "pinned"]);
});
t("a swap that cleared the owner before moving it would show the popup ownerless and pin the same-name sibling", () => {
  const [bug] = swapped("old");
  assert.deepStrictEqual(bug.ownerless, ["media"]);
  assert.strictEqual(bug.h.s.mode, "settling");
});
t("HoverPopup's swap sets the owner before Popups.open(..., swap) and never closes or clears the owner", () => {
  const src = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPopup.qml"), "utf8");
  const branch = src.slice(src.indexOf('r.action === "swap"'), src.indexOf('r.action === "close"'));
  assert.match(branch, /Popups\.hover_owner = root;[\s\S]*Popups\.open\([^\n]*, "", false, true\);/);
  assert.ok(branch.indexOf("Popups.hover_owner = root;") < branch.indexOf("Popups.open("), branch);
  assert.doesNotMatch(branch, /Popups\.close\(|hover_owner = null/);
  assert.match(src, /root\.hover_owner !== root && root\.hover_owner\.mode === "hover_open" && root\.hover_owner\.open_here\n\s+&& !!root\.module && Popups\.open_screen_name === root\.module\.screen_name\n\s+&& \(Popups\.open_name !== root\.popup_name \|\| Popups\.open_anchor === root\.module\.island\)/);
  assert.match(src, /interval = r\.mode === "swapping" \? root\.swap_delay : root\.open_delay;/);
  assert.match(src, /property int swap_delay: 60$/m);
  assert.doesNotMatch(src, /hover_ownerChanged/);
});
t("Popups records swap_from before open_name moves; the popup window fades out or grows in from it", () => {
  const popups = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/Popups.qml"), "utf8");
  const open = popups.slice(popups.indexOf("function open(name"), popups.indexOf("function open_with_keyboard"));
  assert.ok(open.indexOf("root.swap_from = Policy.swap_source(") >= 0 && open.indexOf("root.swap_from = Policy.swap_source(") < open.indexOf("open_name = name;"), open);
  assert.ok(open.indexOf("root.measure_swap(") < open.indexOf("open_name = name;"), open);
  const close = popups.match(/function close\(\) \{[^}]*\}/)[0];
  assert.match(close, /swap_from = null;/);
  const popup = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/frames/Popup.qml"), "utf8");
  assert.match(popup, /if \(swap && swap\.to === root\.popup_name\) root\.swap_in\(swap\.extent\);/);
  assert.match(popup, /\} else if \(visible && Popups\.swap_from && Popups\.swap_from\.name === root\.popup_name\) \{[^}]*swap_out_anim\.restart\(\);/);
  assert.match(popup, /Popups\.swap_done\(root\.popup_name\);/);
});
// Review of D: the styled swap path in Popup.qml. These are window animations, which node cannot run; the shadow covers
// how they look, these pin the guards.
const popup_source = () => fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/frames/Popup.qml"), "utf8");
t("a popup swapped away hides without clearing swap_from, which the incoming popup may not have read yet", () => {
  assert.doesNotMatch(popup_source().match(/function finish_swap_out\(\) \{[^}]*\}/)[0], /swap_done/);
});
t("a popup is not settled while its swap-in runs", () => {
  const settled = popup_source().match(/readonly property bool settled: [^\n]*/)[0];
  assert.match(settled, /!swap_in_anim\.running/);
  assert.doesNotMatch(settled, /swap_phase/);
});
t("a swap-out fades the window, accent line and drawer with swap_fade instead of cutting them", () => {
  const popup = popup_source();
  assert.match(popup, /id: swap_out_anim\n\s+NumberAnimation \{ target: root; property: "swap_fade"; to: 0; duration: root\.swap_out_ms \}/);
  assert.match(popup, /clip: true\n\s+opacity: root\.swap_fade/);
  assert.match(popup, /opacity: root\.line_progress > 0 \? root\.swap_fade : 0/);
  assert.match(popup, /active: root\.drawer\n\s+opacity: root\.swap_fade/);
});
t("no style has its own swap transition: nothing of the styled swap is left", () => {
  const dir = path.join(__dirname, "../.config/quickshell");
  const read = (f) => fs.readFileSync(path.join(dir, f), "utf8");
  assert.doesNotMatch(read("features/popups/frames/Popup.qml"), /SwapFx|swap_phase|swap_fx_on|swap_kind/);
  assert.ok(!fs.existsSync(path.join(dir, "features/popups/frames/SwapFx.qml")));
  assert.doesNotMatch(read("theme/transitions/Kinds.js"), /swap_/);
  for (const f of ["TextureFx", "CoverFx"]) assert.doesNotMatch(read("theme/transitions/" + f + ".qml"), /stop_at|time_scale/, f);
});

let failed = 0;
for (const [name, fn] of cases) {
  try { fn(); console.log("ok   " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message); }
}
process.exit(failed ? 1 : 0);
