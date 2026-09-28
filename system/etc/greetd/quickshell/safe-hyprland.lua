-- /etc/greetd/quickshell/safe-hyprland.lua
-- Minimal Hyprland config for the Options menu's "Safe session": independent of the user's dotfiles.

---- [MONITORS] ----
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})

---- [KEYBINDS] ----
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + Q", hl.dsp.window.kill())
hl.bind("SUPER + M", hl.dsp.exit())

---- [START UP] ----
hl.on("hyprland.start", function()
	hl.exec_cmd("kitty")
end)
