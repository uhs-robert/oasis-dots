// Runs HoverPolicy.js under node: the hover-open state machine behind HoverPopup. The tests play the timers by hand,
// firing each event the way the QML helper would, so the lifecycle races are checked without a compositor.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");

const source = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPolicy.js"), "utf8");
const T = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, "") + "\nthis.api = { inside_changed, open_elapsed, close_elapsed, clicked, popup_changed, nothing_open_now, popup_pressed, disabled, open_here };", T);
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
t("the click-to-open modules opt in; Start, Tray and Media do not", () => {
  for (const m of ["Battery", "Bluetooth", "Network", "Volume", "Updates", "System", "Weather", "Keeptabs", "Notifications"]) {
    assert.match(module_source(m), /^\s+hover_popup: true$/m, m);
  }
  for (const m of ["StartButton", "Tray", "Media"]) assert.doesNotMatch(module_source(m), /hover_popup: true/, m);
});
t("Notifications hover-opens only with notifications", () => {
  assert.match(module_source("Notifications"), /hover_ready: NotificationState\.history\.length > 0/);
});
t("the base routes toggle_popup through the helper and drops the tooltip when hover opens", () => {
  const base = module_source("BarModule");
  assert.match(base, /if \(root\.hover_active\) hover\.click\(\);/);
  assert.match(base, /hover_handler\.hovered && !root\.hover_active\) Tooltip\.show/);
  assert.match(base, /onHover_activeChanged: root\.sync_tooltip\(\)/);
  assert.match(base, /&& Popups\.hover_popups$/m);
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
  assert.match(src, /Popups\.hover_owner = r\.mode === "hover_open" \? root : null;\n\s+Popups\.open\(/);
  assert.match(src, /if \(r\.mode === "pinned"\) Popups\.hover_owner = null;/);
  assert.match(fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/Popups.qml"), "utf8"), /function close\(\) \{\n\s+hover_owner = null;/);
});
t("Media's helper honours the global hover switch", () => {
  assert.match(module_source("Media"), /enabled: root\.shown && Popups\.hover_popups/);
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
  assert.match(module_source("BarModule"), /if \(root\.popup_helper\) root\.popup_helper\.click\(\);/);
  assert.match(module_source("Media"), /popup_helper: hover_popup/);
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

// Two helpers on one popup name (the lualine cava slot "s" and the Media module "m") around a Popups model that keeps
// close()'s real order: hover_owner is cleared before open_name. `rule` is how a helper reacts to losing the owner:
// "shared" is 755c90cbc's handler in every helper, immediate; "slot" is the slot's deferred look; "none" is neither.
function twins(rule) {
  const w = { open_name: "", owner: null, pointer: null, queued: false, h: { s: { mode: "idle", open_timer: false, close_timer: false }, m: { mode: "idle", open_timer: false, close_timer: false } } };
  const open_here = n => w.open_name === "media" && (!w.owner || w.owner === n);
  const inside = n => w.pointer === n;
  const apply = (n, r) => {
    const x = w.h[n];
    x.mode = r.mode;
    if (r.open_timer === "start") x.open_timer = true;
    if (r.open_timer === "stop") x.open_timer = false;
    if (r.close_timer === "start") x.close_timer = true;
    if (r.close_timer === "stop") x.close_timer = false;
    if (r.mode === "pinned") set_owner(null);
    if (r.action === "open") { set_owner(r.mode === "hover_open" ? n : null); set_name("media"); }
    else if (r.action === "close" && open_here(n)) close();
  };
  const set_owner = o => {
    w.owner = o;
    if (rule === "shared") for (const n of ["s", "m"]) if (w.h[n].mode === "hover_open" && w.owner !== n && open_here(n)) apply(n, P.popup_pressed(w.h[n].mode));
    if (rule === "slot" && w.h.s.mode === "hover_open") w.queued = true;
  };
  const set_name = name => {
    const was = w.open_name;
    w.open_name = name;
    for (const n of ["s", "m"]) {
      const before = was === "media" && (!w.owner || w.owner === n);
      if (before !== open_here(n)) apply(n, P.popup_changed(w.h[n].mode, open_here(n), inside(n)));
      if (name === "" && was !== "") apply(n, P.nothing_open_now(w.h[n].mode, inside(n)));
    }
  };
  const close = () => { set_owner(null); set_name(""); };
  // Qt.callLater: runs once the call that changed the owner has finished.
  const settle = () => {
    if (!w.queued) return;
    w.queued = false;
    if (w.h.s.mode === "hover_open" && !w.owner && open_here("s")) apply("s", P.popup_pressed("hover_open"));
  };
  w.hover_open = n => { w.pointer = n; apply(n, P.inside_changed("idle", true, true)); w.fire_open(n); };
  w.move = n => { const was = w.pointer; w.pointer = n; if (was) apply(was, P.inside_changed(w.h[was].mode, false, false)); if (n) apply(n, P.inside_changed(w.h[n].mode, true, false)); settle(); };
  w.click = n => {
    apply(n, P.clicked(w.h[n].mode, open_here(n)));
    // The slot's click handler tells every helper on its popup name, like a press inside the popup.
    if (rule === "slot" && n === "s") for (const o of ["s", "m"]) apply(o, P.popup_pressed(w.h[o].mode));
    settle();
  };
  w.fire_open = n => { const x = w.h[n]; if (x.open_timer) { x.open_timer = false; apply(n, P.open_elapsed(x.mode, inside(n), w.open_name === "")); settle(); } };
  w.fire_close = n => { const x = w.h[n]; if (x.close_timer) { x.close_timer = false; apply(n, P.close_elapsed(x.mode, inside(n))); settle(); } };
  // Escape, an outside click and a toggle all end in Popups.close().
  w.close_from_outside = () => { close(); settle(); };
  // A click-open of another popup: the opener pins, clearing the owner, then open_name moves.
  w.open_other = () => { set_owner(null); set_name("other"); settle(); };
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
t("755c90cbc's shared handler pins on every close and on a click-open of another popup (why it was dropped)", () => {
  const closed = twins("shared");
  closed.hover_open("s");
  closed.close_from_outside();
  assert.notStrictEqual(closed.h.s.mode, "pending");
  const other = twins("shared");
  other.hover_open("s");
  other.open_other();
  assert.notStrictEqual(other.h.s.mode, "idle");
});
t("HoverPopup has no ownership handler; the slot alone watches it, and follows the global switch", () => {
  const src = fs.readFileSync(path.join(__dirname, "../.config/quickshell/features/popups/HoverPopup.qml"), "utf8");
  assert.doesNotMatch(src, /hover_ownerChanged/);
  const strip = bar_source("neovim/LualineStrip.qml");
  assert.match(strip, /function onHover_ownerChanged\(\) \{\n\s+if \(slot_popup\.mode === "hover_open"\) Qt\.callLater\(cava_slot\.take_pin\);/);
  assert.match(strip, /!Popups\.hover_owner && slot_popup\.open_here\) Popups\.popup_pressed\(slot_popup\.popup_name\)/);
  assert.match(strip, /slot_popup\.click\(\);\n\s+\/\/[^\n]*\n\s+Popups\.popup_pressed\(slot_popup\.popup_name\);/);
  assert.match(strip, /enabled: cava_slot\.shown && Popups\.hover_popups/);
});

let failed = 0;
for (const [name, fn] of cases) {
  try { fn(); console.log("ok   " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message); }
}
process.exit(failed ? 1 : 0);
