-- home/hypr/.config/hypr/hyprland.lua

--    ██╗  ██╗██╗   ██╗██████╗ ██████╗ ██╗      █████╗ ███╗   ██╗██████╗
--    ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██║     ██╔══██╗████╗  ██║██╔══██╗
--    ███████║ ╚████╔╝ ██████╔╝██████╔╝██║     ███████║██╔██╗ ██║██║  ██║
--    ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██║     ██╔══██║██║╚██╗██║██║  ██║
--    ██║  ██║   ██║   ██║     ██║  ██║███████╗██║  ██║██║ ╚████║██████╔╝
--    ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝

local Config = require("config")

-- ──────────────────────────────────────────────────────────────────────────── #
-- !-- Run startup sequence
-- ──────────────────────────────────────────────────────────────────────────── #
-- stylua: ignore start
local function init()
  Config.setup({
    drm_devices = "/dev/dri/card1:/dev/dri/card2 Hyprland",
    nvidia = { enable = true },
    monitors = {
        { description = "BOE 0x0C8E",                                        mode = "2560x1600@240",    position = "317x1080", scale = 1.6 },
        { description = "HP Inc. HP Z22n G2 6CM8411J1Z",                     mode = "1920x1080@60",     position = "0x0",      scale = 1 },
        { description = "GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48",  mode = "2560x1440@143.97", position = "1920x0",   scale = 1 },
        { description = "HP Inc. HP Z22n G2 6CM8411J22",                     mode = "1920x1080@60",     position = "4480x0",   scale = 1,   transform = 3 },
    },
  })

  require("hyprvim").setup({
    keys = { leader = "SUPER", activate = "SPACE", exit = "ESCAPE" },
    which_key = { auto_show = { disabled = { "NORMAL", "VISUAL", "V-LINE", "Cursor" } },
    },
  })
end
-- stylua: ignore end

init()
