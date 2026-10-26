-- Actions for the pickers and the two HyprVim keys. A function `run`, not Ipc/Cmd: `Menu.picker` falls back to rofi
-- when the bar lacks a provider, and the directory picker follows `app.tui_file_manager`; an IPC call has neither.
-- Menu and hyprvim are required on use, so a headless load needs neither Config nor the optional hyprvim repo.
local Act = require("lib.act") ---@class ActionLib

--- Build the picker closure on each run so Config is read then, not while this file loads.
--- @param menu_function string  A `Menu` function that returns the closure
--- @return fun()
local function picker(menu_function)
  return function() require("lib.actions.menu")[menu_function]()() end
end

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
