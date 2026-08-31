--- @type Config.Monitor[]
-- stylua: ignore start
local MONITORS_LAPTOP = {
    { description = "BOE 0x0C8E",                                        mode = "2560x1600@240",    position = "317x1080", scale = 1.6 },
    { description = "Lenovo Group Limited T22i-30 V81037ZT",             mode = "1920x1080@60",     position = "0x0",      scale = 1 },
    { description = "GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48",  mode = "2560x1440@143.97", position = "1920x0",   scale = 1,   primary = true },
    { description = "HP Inc. HP Z22n G2 6CM8411J22",                     mode = "1920x1080@60",     position = "4480x0",   scale = 1,   transform = 3 },
}

--- @type Config.Monitor[]
-- NOTE: Blank for now till desktop is ported over to Hyprland as well
local MONITORS_DESKTOP = {
    -- { description = "BOE 0x0C8E",                                        mode = "2560x1600@240",    position = "317x1080", scale = 1.6 },
    -- { description = "HP Inc. HP Z22n G2 6CM8411J1Z",                     mode = "1920x1080@60",     position = "0x0",      scale = 1 },
    -- { description = "GIGA-BYTE TECHNOLOGY CO. LTD. G27QC A 0x00000D48",  mode = "2560x1440@143.97", position = "1920x0",   scale = 1 },
    -- { description = "HP Inc. HP Z22n G2 6CM8411J22",                     mode = "1920x1080@60",     position = "4480x0",   scale = 1,   transform = 3 },
}

return {
  drm_devices = "/dev/dri/card1:/dev/dri/card2 Hyprland",
  monitors = function(is_laptop) return is_laptop and MONITORS_LAPTOP or MONITORS_DESKTOP end,
}
