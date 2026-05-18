--- Loads all submap keymap modules.
--- Each require() is an isolated scope — errors in one don't abort others.

require("keymaps.submaps.apps")
require("keymaps.submaps.go")
require("keymaps.submaps.system")
require("keymaps.submaps.screenshot")
require("keymaps.submaps.windows")
require("keymaps.submaps.cursor")
require("keymaps.submaps.resize")
require("keymaps.submaps.move")
