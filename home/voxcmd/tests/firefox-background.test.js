"use strict";
// Plain-node check of background.js against a mocked `browser`: node home/voxcmd/tests/firefox-background.test.js
const assert = require("assert");
const { handle_request, keep_connected } = require("../../../extras/voxcmd-firefox/background.js");

function make_api() {
  const calls = [];
  const tabs = [
    { id: 7, windowId: 2, title: "Docs", url: "https://example.com/", active: true, discarded: false, lastAccessed: 99, incognito: false, pinned: true, hidden: false },
    { id: 8, windowId: 3, title: "Old", url: "https://example.org/", active: false, discarded: true, lastAccessed: 5, incognito: false, pinned: false, hidden: true },
  ];
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
    },
    windows: { update: async (id, props) => calls.push(["windows.update", id, props]) },
  };
  return api;
}

(async () => {
  let api = make_api();
  let reply = await handle_request(api, { id: 1, cmd: "tabs" });
  assert.deepStrictEqual(reply.result[1], {
    tab_id: 8, window_id: 3, title: "Old", url: "https://example.org/", active: false, discarded: true, last_accessed: 5, incognito: false, pinned: false, hidden: true,
  });
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
