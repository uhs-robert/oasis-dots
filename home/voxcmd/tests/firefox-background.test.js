"use strict";
// Plain-node check of background.js against a mocked `browser`: node home/voxcmd/tests/firefox-background.test.js
const assert = require("assert");
const { handle_request, keep_connected } = require("../../../extras/voxcmd-firefox/background.js");

function make_api() {
  const calls = [];
  const tabs = [
    { id: 7, windowId: 2, title: "Docs", url: "https://example.com/", active: true, discarded: false, lastAccessed: 99, incognito: false, pinned: true, hidden: false, width: 2560, height: 1300, favIconUrl: "https://example.com/favicon.ico" },
    { id: 8, windowId: 3, title: "Old", url: "https://example.org/", active: false, discarded: true, lastAccessed: 5, incognito: false, pinned: false, hidden: true },
    { id: 9, windowId: 3, title: "Narrow", url: "https://example.net/", active: false, discarded: false, lastAccessed: 6, incognito: false, pinned: false, hidden: false, width: 800, height: 600 },
  ];
  const find_tab = (id) => {
    const tab = tabs.find((candidate) => candidate.id === id);
    if (!tab) throw new Error(`Invalid tab ID: ${id}`);
    return tab;
  };
  const api = {
    calls,
    tabs: {
      query: async (filter) => (calls.push(["query", filter]), tabs),
      update: async (id, props) => {
        calls.push(["tabs.update", id, props]);
        const tab = tabs.find((candidate) => candidate.id === id);
        if (!tab) throw new Error(`No tab with id: ${id}`);
        return tab;
      },
      get: async (id) => find_tab(id),
      captureTab: async (id, options) => (calls.push(["captureTab", id, options]), `data:image/jpeg;base64,tab${id}`),
      remove: async (id) => (calls.push(["tabs.remove", id]), find_tab(id), undefined),
    },
    windows: { update: async (id, props) => calls.push(["windows.update", id, props]) },
  };
  return api;
}

(async () => {
  let api = make_api();
  let reply = await handle_request(api, { id: 1, cmd: "tabs" });
  assert.deepStrictEqual(reply.result[1], {
    tab_id: 8, window_id: 3, title: "Old", url: "https://example.org/", active: false, discarded: true, last_accessed: 5, incognito: false, pinned: false, hidden: true, fav_icon_url: "",
  });
  assert.strictEqual(reply.result[0].fav_icon_url, "https://example.com/favicon.ico");
  assert.strictEqual(reply.id, 1);
  assert.strictEqual(reply.ok, true);

  api = make_api();
  reply = await handle_request(api, { id: 2, cmd: "activate", tab_id: 8 });
  assert.deepStrictEqual(reply, { id: 2, ok: true, result: { activated: true, title: "Old", window_id: 3, focused: true, preface_set: false } });
  assert.deepStrictEqual(api.calls, [["tabs.update", 8, { active: true }], ["windows.update", 3, { focused: true }]]);

  // A nonce is put in front of the window's title, and cleared by the safety timer if nobody asks.
  api = make_api();
  const timers = [];
  reply = await handle_request(api, { id: 6, cmd: "activate", tab_id: 8, preface: "vx12ab" }, (fn, ms) => timers.push([fn, ms]));
  assert.strictEqual(reply.result.preface_set, true);
  assert.deepStrictEqual(api.calls[2], ["windows.update", 3, { titlePreface: "vx12ab " }]);
  assert.strictEqual(timers[0][1], 10000);
  await timers[0][0]();
  assert.deepStrictEqual(api.calls[3], ["windows.update", 3, { titlePreface: "" }]);
  reply = await handle_request(api, { id: 7, cmd: "clear_preface", window_id: 3 });
  assert.deepStrictEqual(reply, { id: 7, ok: true, result: { cleared: true } });
  // An older activation's timer, or its late clear, leaves a newer nonce on the same window alone.
  api = make_api();
  const later_timers = [];
  await handle_request(api, { id: 10, cmd: "activate", tab_id: 8, preface: "vxold" }, (fn, ms) => later_timers.push(fn));
  await handle_request(api, { id: 11, cmd: "activate", tab_id: 8, preface: "vxnew" }, (fn, ms) => later_timers.push(fn));
  const updates_before = api.calls.length;
  await later_timers[0]();
  reply = await handle_request(api, { id: 12, cmd: "clear_preface", window_id: 3, preface: "vxold" });
  assert.deepStrictEqual(reply.result, { cleared: false });
  assert.strictEqual(api.calls.length, updates_before);
  reply = await handle_request(api, { id: 13, cmd: "clear_preface", window_id: 3, preface: "vxnew" });
  assert.deepStrictEqual(reply.result, { cleared: true });
  assert.deepStrictEqual(api.calls[api.calls.length - 1], ["windows.update", 3, { titlePreface: "" }]);
  reply = await handle_request(make_api(), { id: 8, cmd: "activate", tab_id: 8, preface: "not ok!" });
  assert.strictEqual(reply.ok, false);

  // The tab switching is reported even when the window cannot be focused.
  api = make_api();
  api.windows.update = async () => {
    throw new Error("window gone");
  };
  reply = await handle_request(api, { id: 9, cmd: "activate", tab_id: 8, preface: "vx12ab" }, () => {});
  assert.strictEqual(reply.ok, true);
  assert.strictEqual(reply.result.activated, true);
  assert.strictEqual(reply.result.focused, false);
  assert.strictEqual(reply.result.preface_set, false);

  reply = await handle_request(make_api(), { id: 3, cmd: "activate", tab_id: 404 });
  assert.deepStrictEqual(reply, { id: 3, ok: false, error: "No tab with id: 404" });
  reply = await handle_request(make_api(), { id: 4, cmd: "activate", tab_id: "7" });
  assert.strictEqual(reply.ok, false);
  reply = await handle_request(make_api(), { id: 5, cmd: "open", url: "https://example.com" });
  assert.deepStrictEqual(reply, { id: 5, ok: false, error: "unknown command: open" });

  // A capture is a scaled-down JPEG of the tab, fitted in 1280x960 and never scaled up; the URL comes with it.
  api = make_api();
  reply = await handle_request(api, { id: 20, cmd: "capture_tab", tab_id: 7 });
  assert.deepStrictEqual(reply, { id: 20, ok: true, result: { tab_id: 7, url: "https://example.com/", data_url: "data:image/jpeg;base64,tab7" } });
  assert.deepStrictEqual(api.calls, [["captureTab", 7, { format: "jpeg", quality: 80, scale: 0.5 }]]);
  await handle_request(api, { id: 21, cmd: "capture_tab", tab_id: 9 });
  assert.strictEqual(api.calls[1][2].scale, 1);
  // A discarded tab is refused, not loaded to be captured.
  api = make_api();
  reply = await handle_request(api, { id: 22, cmd: "capture_tab", tab_id: 8 });
  assert.deepStrictEqual(reply, { id: 22, ok: false, error: "the tab is not loaded" });
  assert.deepStrictEqual(api.calls, []);
  reply = await handle_request(api, { id: 23, cmd: "capture_tab", tab_id: 404 });
  assert.deepStrictEqual(reply, { id: 23, ok: false, error: "Invalid tab ID: 404" });
  reply = await handle_request(api, { id: 24, cmd: "capture_tab" });
  assert.strictEqual(reply.ok, false);
  api.tabs.captureTab = async () => {
    throw new Error("capture refused");
  };
  reply = await handle_request(api, { id: 25, cmd: "capture_tab", tab_id: 7 });
  assert.deepStrictEqual(reply, { id: 25, ok: false, error: "capture refused" });

  api = make_api();
  reply = await handle_request(api, { id: 26, cmd: "close", tab_id: 9 });
  assert.deepStrictEqual(reply, { id: 26, ok: true, result: { closed: true } });
  assert.deepStrictEqual(api.calls, [["tabs.remove", 9]]);
  reply = await handle_request(api, { id: 27, cmd: "close", tab_id: 404 });
  assert.deepStrictEqual(reply, { id: 27, ok: false, error: "Invalid tab ID: 404" });
  reply = await handle_request(api, { id: 28, cmd: "close", tab_id: "9" });
  assert.strictEqual(reply.ok, false);

  // Reconnect: each drop schedules a connect with a doubling pause, capped; a request resets it.
  const ports = [];
  const connecting = {
    runtime: {
      connectNative: (name) => {
        assert.strictEqual(name, "voxcmd_firefox");
        const port = { sent: [], handlers: {} };
        port.postMessage = (message) => port.sent.push(message);
        port.onMessage = { addListener: (fn) => (port.handlers.message = fn) };
        port.onDisconnect = { addListener: (fn) => (port.handlers.disconnect = fn) };
        ports.push(port);
        return port;
      },
    },
    ...make_api(),
  };
  const waits = [];
  let pending_connect = null;
  keep_connected(connecting, (fn, ms) => ((pending_connect = fn), waits.push(ms)));
  for (let drop = 0; drop < 7; drop++) {
    ports[ports.length - 1].handlers.disconnect();
    pending_connect();
  }
  assert.deepStrictEqual(waits, [1000, 2000, 4000, 8000, 16000, 30000, 30000]);
  await ports[ports.length - 1].handlers.message({ id: 9, cmd: "tabs" });
  assert.strictEqual(ports[ports.length - 1].sent[0].id, 9);
  ports[ports.length - 1].handlers.disconnect();
  assert.strictEqual(waits[waits.length - 1], 1000);
  console.log("ok");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
