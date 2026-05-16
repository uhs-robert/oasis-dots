--- Central keymap entry point.
--- Registers global binds then loads all submap definitions.
--- Called once at Hyprland startup from config/init.lua.

local Keymaps = {}

function Keymaps.setup()
  require("keymaps.global").setup()
  require("keymaps.submaps.apps").setup()
  require("keymaps.submaps.go").setup()
  require("keymaps.submaps.system").setup()
  require("keymaps.submaps.screenshot").setup()
  require("keymaps.submaps.windows").setup()
  require("keymaps.submaps.cursor").setup()
  require("keymaps.submaps.resize").setup()
  require("keymaps.submaps.move").setup()
end

return Keymaps
