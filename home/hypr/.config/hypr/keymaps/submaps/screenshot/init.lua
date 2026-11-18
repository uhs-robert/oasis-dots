--- Screenshot submap
--- Carries the keys of the bar's screenshot menu, which opens hands-off so the window under it keeps focus. The bar
--- enters this submap when it opens the menu and leaves it when the menu closes; there is no entry key here.

local Submap = require("lib.key.submap") --- @class Submap

require("lib.act.defs.screenshot")

-- Rows keep the submap: the bar leaves it once the menu has closed. Exiting first would close the menu from the submap
-- event before the row's IPC call lands, and a frozen capture could catch the menu mid-fold.
local KEEP = { keep = true }

local function row(key, menu_key, label) return { key, { "screenshot.menu_key", { menu_key } }, label, KEEP } end

local menu = Submap.define({
  name = "Screenshot",
  desc = "+Screenshot",

  escape = "reset",
  catchall = "reset",

  -- The keys of Screenshot.menu_rows in the bar (features/screenshot/Screenshot.qml); change both together.
  -- stylua: ignore start
  binds = {
    row("R",         "r", "Region"),
    row("I",         "i", "Region"),
    row("Z",         "z", "Frozen region"),
    row("S",         "s", "Screen"),
    row("W",         "w", "Window"),
    row("F",         "f", "Focused window"),
    row("SHIFT + R", "R", "Record region"),
    row("SHIFT + W", "W", "Record window"),
    row("SHIFT + S", "S", "Record screen"),
    row("SHIFT + F", "F", "Record focused"),
    row("P",         "p", "Pick pixel color"),
    row("T",         "t", "Text from region"),
    row("X",         "x", "Scroll text (OCR)"),
    row("SHIFT + X", "X", "Scroll capture (image)"),
  },
  -- stylua: ignore end
})
menu.setup()

-- The bar calls these through `hyprctl dispatch "ScreenshotMenu.enter()"`, which dispatches the result, hence no_op.
_G.ScreenshotMenu = {
  enter = function()
    menu.enter()
    return hl.dsp.no_op()
  end,
  -- Only out of this submap: the menu can close after a row has already moved on to another one.
  leave = function()
    if Submap.current == "Screenshot" then Submap.reset() end
    return hl.dsp.no_op()
  end,
}
