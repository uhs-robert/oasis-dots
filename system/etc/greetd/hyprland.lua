---- [GLOBALS] ----
GREETD_DIRECTORY = "/etc/greetd"
ADMIN = "roberth"
TERMINAL = "kitty"

---- [ENV] ----
hl.env("PATH", "/usr/bin")
hl.env("KITTY_CACHE_DIRECTORY", "/var/lib/greetd/kitty-cache")
hl.env("KITTY_RUNTIME_DIRECTORY", "/var/lib/greetd/kitty-runtime")
hl.env("KITTY_CONFIG_DIRECTORY", GREETD_DIRECTORY)
hl.env("XDG_RUNTIME_DIR", "/run/user/962")
hl.env("WAYLAND_DISPLAY", "wayland-1")

---- [FUNCTIONS] ----
function FULLSCREEN_TERMINAL()
	hl.dispatch(hl.dsp.window.fullscreen({ action = "set", mode = "fullscreen", window = "class:" .. TERMINAL }))
end

local restart_login = function()
	hl.dispatch(hl.dsp.window.kill())
	hl.dispatch(hl.dsp.exec_cmd("hyprshutdown"))
end

---- [KEYBINDS] ----
hl.bind(
	"SUPER + RETURN",
	hl.dsp.exec_cmd(TERMINAL .. " --title admin-shell --directory " .. GREETD_DIRECTORY .. " -- su " .. ADMIN)
)
hl.bind("SUPER + X", hl.dsp.window.kill())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind("SUPER + Q", restart_login)

---- [MONITORS] ----
-- MAIN
hl.monitor({
	output = "desc:BOE 0x0C8E",
	mode = "1920x1080@60",
	scale = 1,
	position = "auto",
})

-- MIRRORS
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
	mirror = "eDP-1",
})

---- [ADMIN TERMINAL FULLSCREEN] ----
hl.window_rule({
	name = "admin-shell-fullscreen",
	match = {
		class = "kitty",
		title = "admin-shell",
	},
	fullscreen = true,
})

---- [HL CONFIG] ----
hl.config({
	general = {
		gaps_in = 1,
		gaps_out = 1,
		border_size = 0,
	},
	decoration = {
		shadow = {
			enabled = false,
		},
		blur = {
			enabled = false,
		},
	},
	misc = {
		background_color = "#0C0E13",
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		disable_hyprland_guiutils_check = true,
	},
	cursor = {
		invisible = true,
	},
	ecosystem = {
		no_donation_nag = true,
		no_update_news = true,
	},
})

---- [START UP] ----
hl.on("hyprland.start", function()
	hl.exec_cmd(
		"setfacl -m u:"
			.. ADMIN
			.. ":x /run/user/962; setfacl -m u:"
			.. ADMIN
			.. ":rw /run/user/962/wayland-1; "
			.. TERMINAL
			.. " -- tuigreet --config /etc/tuigreet/config.toml --debug /tmp/tuigreet.log &"
			.. "terminal_pid=$!; "
			.. "sleep 1.5; "
			.. "hyprctl eval 'FULLSCREEN_TERMINAL()'; "
			.. "wait $terminal_pid; "
			.. "hyprctl dispatch 'hl.dsp.exit()'"
	)
end)
