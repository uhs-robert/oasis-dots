---- [GLOBALS] ----
GREETD_DIRECTORY = "/etc/greetd"
local function valid_user(name)
	return name and name:match("^[a-z_][a-z0-9_-]*$") and name or nil
end

local function resolve_admin()
	local file = io.open(GREETD_DIRECTORY .. "/admin_user")
	if file then
		local name = valid_user(file:read("*l"))
		file:close()
		if name then
			return name
		end
	end
	for line in io.lines("/etc/passwd") do
		local name, uid, shell = line:match("^([^:]+):[^:]*:(%d+):[^:]*:[^:]*:[^:]*:([^:]*)$")
		uid = tonumber(uid)
		if valid_user(name) and uid >= 1000 and uid < 60000 and not shell:match("nologin$") and not shell:match("false$") then
			return name
		end
	end
end

ADMIN = resolve_admin()
RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR")
if not RUNTIME_DIR or RUNTIME_DIR == "" then
	local uid_pipe = io.popen("id -u")
	RUNTIME_DIR = "/run/user/" .. uid_pipe:read("*l")
	uid_pipe:close()
end
TERMINAL = "kitty"

---- [ENV] ----
hl.env("PATH", "/usr/bin")
hl.env("KITTY_CACHE_DIRECTORY", "/var/lib/greetd/kitty-cache")
hl.env("KITTY_RUNTIME_DIRECTORY", "/var/lib/greetd/kitty-runtime")
hl.env("KITTY_CONFIG_DIRECTORY", GREETD_DIRECTORY)
hl.env("XDG_RUNTIME_DIR", RUNTIME_DIR)
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
if ADMIN then
	hl.bind(
		"SUPER + RETURN",
		hl.dsp.exec_cmd(TERMINAL .. " --title admin-shell --directory " .. GREETD_DIRECTORY .. " -- su " .. ADMIN)
	)
end
hl.bind("SUPER + X", hl.dsp.window.kill())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind("SUPER + Q", restart_login)
-- Swap the Quickshell greeter for tuigreet (qs-greeter falls back when qs exits after this marker).
hl.bind("SUPER + T", hl.dsp.exec_cmd("mkdir -p " .. RUNTIME_DIR .. "/qs-greeter; touch " .. RUNTIME_DIR .. "/qs-greeter/fallback; pkill -x qs; sleep 1; pkill -9 -x qs"))

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
	xwayland = {
		enabled = false,
	},
	ecosystem = {
		no_donation_nag = true,
		no_update_news = true,
	},
})

---- [START UP] ----
hl.on("hyprland.start", function()
	local admin_acl = ADMIN
			and ("setfacl -m u:" .. ADMIN .. ":x " .. RUNTIME_DIR .. "; setfacl -m u:" .. ADMIN .. ":rw " .. RUNTIME_DIR .. "/wayland-1; ")
		or ""
	hl.exec_cmd(
		admin_acl
			.. "if [ -x /usr/local/bin/qs-greeter ]; then /usr/local/bin/qs-greeter; else "
			.. TERMINAL
			.. " -- tuigreet --config /etc/tuigreet/config.toml --debug /tmp/tuigreet.log &"
			.. "terminal_pid=$!; "
			.. "sleep 1.5; "
			.. "hyprctl eval 'FULLSCREEN_TERMINAL()'; "
			.. "wait $terminal_pid; fi; "
			.. "hyprctl dispatch 'hl.dsp.exit()'"
	)
end)
