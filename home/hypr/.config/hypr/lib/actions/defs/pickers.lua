-- Actions for the pickers and the HyprVim keys. A function `run`, not Ipc/Cmd: `Menu.picker` falls back to rofi
-- when the bar lacks a provider, and the directory picker follows `app.tui_file_manager`; an IPC call has neither.
-- Menu and hyprvim are required on use, so a headless load needs neither Config nor the optional hyprvim repo.
local Act = require("lib.act") ---@class ActionLib
local Defer = require("lib.actions.defer") ---@class Defer

local picker = function(menu_function) return Defer.call("lib.actions.menu", menu_function) end

Act.define("picker.clipboard", {
  label = "Clipboard History",
  intent = "Pick an entry from the clipboard history and copy it.",
  key = { key = "CTRL + V", leader = true },
  run = picker("clipboard"),
})

Act.define("picker.clipboard_delete", {
  label = "Delete Clipboard Entry",
  intent = "Pick an entry from the clipboard history and delete it.",
  key = { key = "CTRL + SHIFT + V", leader = true },
  run = picker("clipboard_delete"),
})

Act.define("picker.directory", {
  label = "Jump to Directory",
  intent = "Pick a frequently used directory and open it in the file manager.",
  key = { key = "CTRL + SPACE", leader = true },
  run = picker("zoxide"),
})

Act.define("picker.emoji", {
  label = "Emoji Picker",
  intent = "Pick an emoji and type it into the focused window.",
  key = { key = "CTRL + E", leader = true },
  run = picker("emoji"),
})

Act.define("hyprvim.terminal", {
  label = "HyprVim Terminal",
  intent = "Open HyprVim's command prompt.",
  key = { key = "SHIFT + SEMICOLON", leader = true },
  run = function() require("lua.plugins.hyprvim").command.prompt() end,
})

Act.define("hyprvim.jump_mark", {
  label = "Jump to Mark",
  intent = "Jump to a window or workspace mark set in HyprVim.",
  key = { key = "APOSTROPHE", leader = true },
  run = function() require("lua.plugins.hyprvim").marks.enter_jump() end,
})

Act.define("hyprvim.edit_selection", {
  label = "Edit Selection in Vim",
  intent = "Open the selected text in HyprVim's editor, in insert mode.",
  key = { key = "N", leader = true },
  run = function() require("lua.plugins.hyprvim").editor.open({ insert_mode = true }) end,
})
