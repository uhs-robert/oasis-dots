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

let failed = 0;
for (const [name, fn] of cases) {
  try { fn(); console.log("ok   " + name); } catch (e) { failed++; console.log("FAIL " + name + "\n  " + e.message); }
}
process.exit(failed ? 1 : 0);
