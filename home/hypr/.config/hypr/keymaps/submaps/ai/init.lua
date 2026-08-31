--- AI command submap
--- Tool keys toggle VoxType recording on/off.
--- Bare keys submit the prompt. Ctrl variants prefill without submitting.
--- Escape exits the submap.

local AI = require("lib.actions.ai") --- @class AI
local Config = require("config") --- @class Config
local Submap = require("lib.key.submap") --- @class Submap

Submap.define({
  name = "AI",
  desc = "+AI",
  enter = Config.leader .. " + SHIFT + A",

  escape = "reset",
  catchall = "stay",
  on_enter = function()
    if AI.is_visible() then
      AI.hide()
      Submap.reset()
    else
      AI.show()
    end
  end,
  on_exit = AI.finish,

  -- stylua: ignore
  binds = {
    { "PERIOD",     function() AI.toggle("", false) end,            "Talk to Agent (Prefill)" },
    { "X",          function() AI.send_text("/clear") end,          "Clear" },
    { "BACKSPACE",  AI.cancel,                                      "Cancel Recording" },

    { "G",          function() AI.toggle("use gog to", false) end,                 "Gog (Prefill)" },
    { "CTRL + G",   function() AI.toggle("use gog to", true) end,                  "Gog" },

    { "H",          function() AI.toggle("use gh to", false) end,                  "GitHub (Prefill)" },
    { "CTRL + H",   function() AI.toggle("use gh to", true) end,                   "GitHub" },

    { "B",          function() AI.toggle("use agent-browser to", false) end,       "Browser (Prefill)" },
    { "CTRL + B",   function() AI.toggle("use agent-browser to", true) end,        "Browser" },

    { "S",          function() AI.toggle("use the shell and available system tools to", false) end, "System (Prefill)" },
    { "CTRL + S",   function() AI.toggle("use the shell and available system tools to", true) end,  "System" },
  },
}).setup()
