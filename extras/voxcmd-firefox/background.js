"use strict";

const HOST_NAME = "voxcmd_firefox";
const FIRST_RETRY_MS = 1000;
const LAST_RETRY_MS = 30000;
// The preface marking a window is cleared by the client; this is for a client that died before it did.
const PREFACE_LIFETIME_MS = 10000;

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
    hidden: Boolean(tab.hidden),
  };
}

async function list_tabs(api) {
  return (await api.tabs.query({})).map(describe_tab);
}

// Selecting the tab is the part that matters, so it is reported as done whatever happens to the window after it.
// Firefox does not reliably raise the window of a tab it selects, so the window is focused too. The compositor needs to
// tell that window from others showing the same title, so the caller's nonce is put in front of the window's title
// until it asks for it back (clear_preface).
async function activate_tab(api, request, schedule) {
  const { tab_id, preface } = request;
  if (!Number.isInteger(tab_id)) {
    throw new Error("activate needs an integer tab_id");
  }
  if (preface !== undefined && !/^[A-Za-z0-9]{1,32}$/.test(preface)) {
    throw new Error("preface is letters and digits only");
  }
  const tab = await api.tabs.update(tab_id, { active: true });
  const result = { activated: true, title: tab.title || "", window_id: tab.windowId, focused: false, preface_set: false };
  try {
    await api.windows.update(tab.windowId, { focused: true });
    result.focused = true;
  } catch (error) {
    result.focus_error = String((error && error.message) || error);
  }
  if (preface !== undefined) {
    try {
      await api.windows.update(tab.windowId, { titlePreface: `${preface} ` });
      result.preface_set = true;
      schedule(() => clear_preface(api, tab.windowId).catch(() => {}), PREFACE_LIFETIME_MS);
    } catch (error) {
      result.preface_error = String((error && error.message) || error);
    }
  }
  return result;
}

async function clear_preface(api, window_id) {
  if (!Number.isInteger(window_id)) {
    throw new Error("clear_preface needs an integer window_id");
  }
  await api.windows.update(window_id, { titlePreface: "" });
  return { cleared: true };
}

async function handle_request(api, request, schedule = setTimeout) {
  const { id, cmd } = request;
  try {
    let result;
    if (cmd === "tabs") {
      result = await list_tabs(api);
    } else if (cmd === "activate") {
      result = await activate_tab(api, request, schedule);
    } else if (cmd === "clear_preface") {
      result = await clear_preface(api, request.window_id);
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
