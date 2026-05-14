-- home/hypr/.config/hypr/theme/generate/hyprland.lua

--- Applies theme colors to Hyprland borders and shadow via hl.config().
--- @param c table Palette color table from theme.colors.*
return function(c)
  hl.config({
    general = {
      col = {
        active_border = c.theme_primary,
        inactive_border = c.bg_mantle,
      },
    },
    decoration = {
      shadow = { color = c.bg_shadow },
    },
  })
end
