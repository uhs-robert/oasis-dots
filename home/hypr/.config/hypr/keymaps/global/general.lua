local Act = require("lib.act") ---@class ActionLib
local Config = require("config") ---@class Config
local Direction = require("lib.key.direction") ---@class Direction

require("lib.actions.defs.windows")

Act.bind("help.keybinds", { key = { key = "SLASH", leader = true, universal = true } })
Act.bind("window.close", { key = { key = "X", leader = true } })
Act.bind("window.fullscreen", { key = { key = "F", leader = true } })
Act.bind("window.maximize", { key = { key = "M", leader = true } })
Act.bind("window.restore_closed", { key = { key = "U", leader = true } })
Act.bind("scratchpad.toggle", { key = { key = "S", leader = true, universal = true } })
Act.bind("scratchpad.move", { key = { key = "SHIFT + S", leader = true, universal = true } })

-- Focus and Move Window: the keys follow Config.vim_mode (the letter or the arrow carries the which-key label).
local DIRECTIONS = {
  { name = "left", title = "Left", letter = "H", arrow = "LEFT" },
  { name = "down", title = "Down", letter = "J", arrow = "DOWN" },
  { name = "up", title = "Up", letter = "K", arrow = "UP" },
  { name = "right", title = "Right", letter = "L", arrow = "RIGHT" },
}

--- @param id     string  An action with one `dir` param
--- @param prefix string  Modifier before the key, "" or "SHIFT + "
--- @param label  string  Which-key label before the direction
local function bind_directions(id, prefix, label)
  for _, direction in ipairs(DIRECTIONS) do
    local shown, hidden = Direction.keys(direction.letter, direction.arrow)
    local args = { direction.name }
    Act.bind(id, {
      key = { key = prefix .. shown, leader = true, universal = true },
      args = args,
      desc = label .. " " .. direction.title,
    })
    Act.bind(id, { key = { key = prefix .. hidden, leader = true, universal = true }, args = args, desc = false })
  end
end

bind_directions("window.focus", "", "Focus")
bind_directions("window.move", "SHIFT + ", "Move Window")

-- Float Cycle (notification toasts first)
Act.bind("window.cycle_float", {
  key = { key = "BRACKETLEFT", leader = true },
  args = { "prev" },
  desc = "Prev Toast/Popup/Float",
})
Act.bind("window.cycle_float", {
  key = { key = "BRACKETRIGHT", leader = true },
  args = { "next" },
  desc = "Next Toast/Popup/Float",
})

-- Monitor Focus/Movement
for slot = 1, #Config.monitors > 0 and math.min(#Config.monitors, 10) or 10 do
  local key = slot % 10
  Act.bind("monitor.focus", {
    key = { key = "CTRL + " .. key, leader = true },
    args = { slot },
    desc = "Focus Monitor " .. slot,
  })
  Act.bind("monitor.move_window", {
    key = { key = "CTRL + SHIFT + " .. key, leader = true },
    args = { slot },
    desc = "Move to Monitor " .. slot,
  })
end
