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
-- monitors.lua is generated at install time from the owner's session config (lib/install/greeter-monitors.lua). A missing
-- or broken file must leave login working, so a failure only costs the explicit layout; the catch-all below still lights
-- every output.
GREETER_HELD = {}
local loaded, load_error = pcall(dofile, GREETD_DIRECTORY .. "/monitors.lua")
if not loaded and not tostring(load_error):find("No such file", 1, true) then
	io.stderr:write("greetd: monitors.lua failed: ", tostring(load_error), "\n")
end

-- Outputs the generated rules do not name
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

---- [LATE MONITORS] ----
-- Hyprland 0.57 aborts when a dock monitor comes up before the dock has settled (hyprwm/Hyprland#16727): building its
-- framebuffer asserts on a zero size, and a disabled monitor is skipped there. So each GREETER_HELD monitor starts
-- disabled.
--
-- The hold also keeps the dock dark for the greeter's whole life. Every dock modeset makes the MST hub reset its link, and
-- each reset risks a boot with both dock monitors on "No signal", so the session should be the one modeset. The timer
-- lights the dock only when no other monitor is lit (undocked, lid closed, HDMI off), because the login screen would
-- otherwise be blank. It does that by reloading the config, which applies the rules directly; the marker makes that
-- reload skip the hold. A plain hl.monitor() rule is no use here: it lands only on another monitor's next frame.
local released_marker = RUNTIME_DIR .. "/hypr/" .. (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") .. "/greeter-monitors-released"
local handed_off = false

local function released_before()
	local file = io.open(released_marker, "r")
	if file then
		file:close()
	end
	return file ~= nil
end

-- Matches by description like the rules do, never by connector name, which gets recycled. Skipping held monitors also
-- keeps the count right if Hyprland lists a disabled monitor.
local function lit_non_dock_count()
	local held_outputs = {}
	for _, held in ipairs(GREETER_HELD) do
		held_outputs[held.rule.output] = true
	end
	local count = 0
	for _, monitor in ipairs(hl.get_monitors() or {}) do
		if not (held_outputs["desc:" .. tostring(monitor.description)] or held_outputs[monitor.name]) then
			count = count + 1
		end
	end
	return count
end

-- One timer at the longest delay decides for every held monitor at once: a release reloads the config, which would
-- otherwise end the hold of the others early.
local function release_all()
	if handed_off or lit_non_dock_count() > 0 then
		return
	end
	local file = io.open(released_marker, "w")
	if file then
		file:close()
	end
	hl.dispatch(hl.dsp.reload_config())
end

local holding, longest_delay = not released_before(), 0
for _, held in ipairs(GREETER_HELD) do
	if holding then
		hl.monitor({ output = held.rule.output, disabled = true })
		longest_delay = math.max(longest_delay, held.delay)
	else
		hl.monitor(held.rule)
	end
end
if longest_delay > 0 then
	hl.timer(release_all, { timeout = longest_delay, type = "oneshot" })
end

-- Called right before the greeter exits. After a forced teardown of the dock on exit, amdgpu left those monitors on
-- "No signal" in the session that starts next. The flag stops a timer still pending from turning them back on. A dock
-- that was never lit needs no teardown, and disabling it again would only cost another modeset. The release reloads this
-- file, which resets every local, so only the marker still says whether the dock was lit.
function GREETER_HANDOFF()
	handed_off = true
	if not released_before() then
		return
	end
	for _, held in ipairs(GREETER_HELD) do
		hl.monitor({ output = held.rule.output, disabled = true })
	end
end

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
			.. (#GREETER_HELD > 0 and "hyprctl eval 'GREETER_HANDOFF()'; sleep 1; " or "")
			.. "hyprctl dispatch 'hl.dsp.exit()'"
	)
end)
