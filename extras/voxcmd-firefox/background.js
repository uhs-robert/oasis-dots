"use strict";

const HOST_NAME = "voxcmd_firefox";
const FIRST_RETRY_MS = 1000;
const LAST_RETRY_MS = 30000;

function describe_tab(tab) {
  return {
    tab_id: tab.id,
    window_id: tab.windowId,
    title: tab.title || "",
    url: tab.url || "",
    active: Boolean(tab.active),
    discarded: Boolean(tab.discarded),
    last_accessed: tab.lastAccessed || 0,
    incognito: Boolean(tab.incognito),
    pinned: Boolean(tab.pinned),
  };
}

async function list_tabs(api) {
  return (await api.tabs.query({})).map(describe_tab);
}

// Firefox does not raise the window for a tab it activates, so the window is focused as well.
async function activate_tab(api, tab_id) {
  if (!Number.isInteger(tab_id)) {
    throw new Error("activate needs an integer tab_id");
  }
  const tab = await api.tabs.update(tab_id, { active: true });
  await api.windows.update(tab.windowId, { focused: true });
  return { title: tab.title || "", window_id: tab.windowId };
}

async function handle_request(api, request) {
  const { id, cmd } = request;
  try {
    let result;
    if (cmd === "tabs") {
      result = await list_tabs(api);
    } else if (cmd === "activate") {
      result = await activate_tab(api, request.tab_id);
    } else {
      throw new Error(`unknown command: ${cmd}`);
    }
    return { id, ok: true, result };
  } catch (error) {
    return { id, ok: false, error: String((error && error.message) || error) };
  }
}

// One long-lived port; the host exits when it is dropped, so a drop is retried with a growing pause.
function keep_connected(api, schedule) {
  let retry_ms = FIRST_RETRY_MS;
  function connect() {
    const port = api.runtime.connectNative(HOST_NAME);
    port.onMessage.addListener(async (request) => {
      retry_ms = FIRST_RETRY_MS;
      port.postMessage(await handle_request(api, request));
    });
    port.onDisconnect.addListener(() => {
      schedule(connect, retry_ms);
      retry_ms = Math.min(retry_ms * 2, LAST_RETRY_MS);
    });
  }
  connect();
}

if (typeof module !== "undefined") {
  module.exports = { handle_request, keep_connected };
} else {
  keep_connected(browser, setTimeout);
}
