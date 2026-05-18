--- Global keybinds — workspace navigation, shortcuts, tools, media, mouse.
--
--    ██╗  ██╗███████╗██╗   ██╗██████╗ ██╗███╗   ██╗██████╗ ███████╗
--    ██║ ██╔╝██╔════╝╚██╗ ██╔╝██╔══██╗██║████╗  ██║██╔══██╗██╔════╝
--    █████╔╝ █████╗   ╚████╔╝ ██████╔╝██║██╔██╗ ██║██║  ██║███████╗
--    ██╔═██╗ ██╔══╝    ╚██╔╝  ██╔══██╗██║██║╚██╗██║██║  ██║╚════██║
--    ██║  ██╗███████╗   ██║   ██████╔╝██║██║ ╚████║██████╔╝███████║
--    ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝
--
-- Each section is a separate require() so errors in one don't abort the others.

require("keymaps.global.general")
require("keymaps.global.workspace")
require("keymaps.global.shortcuts")
require("keymaps.global.tools")
require("keymaps.global.media")
require("keymaps.global.mouse")
