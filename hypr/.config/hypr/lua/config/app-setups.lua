-- hypr/.config/hypr/lua/config/app-setups.lua
-- Application and setup definitions for auto-launch

local Config = {}

-- ========== HELPER FUNCTIONS ========== --

-- Create tmuxifier session launcher
local function tmuxifier(session, monitor)
	monitor = monitor or "RIGHT"
	return {
		monitor = monitor,
		increment = true,
		cmd = string.format("kitty -e tmuxifier load-session %s", session),
	}
end

-- Create tmux session launcher
local function tmux_session(name, monitor)
	monitor = monitor or "RIGHT"
	return {
		monitor = monitor,
		increment = true,
		cmd = string.format("kitty -e tmux new -A -s %s", name),
	}
end

-- ========== REUSABLE APP BLOCKS ========== --

Config.apps = {
	-- Firefox: triple monitor default
	firefox_triple = {
		{ monitor = "CENTER", increment = true, cmd = "firefox" },
		{ monitor = "PRIMARY", increment = true, cmd = "firefox" },
		{ monitor = "LEFT", increment = true, cmd = "firefox" },
	},

	-- Email client
	email = {
		{ monitor = "PRIMARY", increment = false, cmd = "flatpak run eu.betterbird.Betterbird" },
	},

	-- Slack
	slack = {
		{ monitor = "PRIMARY", increment = true, cmd = "slack" },
	},

	-- File managers
	yazi = {
		{ monitor = "RIGHT", increment = true, cmd = "kitty -e yazi" },
	},

	dolphin = {
		{ monitor = "CENTER", increment = true, cmd = "dolphin" },
	},

	-- Monitoring tools
	journal = {
		{ monitor = "CENTER", increment = true, cmd = "kitty -e journalctl -f" },
	},

	btop = {
		{ monitor = "RIGHT", increment = true, cmd = "kitty -e btop" },
	},
}

-- ========== SETUP DEFINITIONS ========== --

Config.setups = {
	["🌐 Browsing"] = {
		Config.apps.firefox_triple,
		tmuxifier("config"),
	},

	["🧱 Client"] = {
		Config.apps.firefox_triple,
		tmuxifier("client-dev"),
		tmuxifier("config", "CENTER"),
		Config.apps.slack,
		Config.apps.email,
	},

	["🛠 Config"] = {
		Config.apps.firefox_triple,
		tmuxifier("config"),
		Config.apps.email,
	},

	["🗂 Files"] = {
		Config.apps.dolphin,
		Config.apps.yazi,
	},

	["🧩 Game Mods"] = {
		{ monitor = "LEFT", increment = true, cmd = "steam" },
		{ monitor = "CENTER", increment = true, cmd = "kitty -d ~/Downloads/ yazi" },
		{ monitor = "RIGHT", increment = true, cmd = "kitty -d ~/.steam/steam/steamapps/ yazi" },
	},

	["🎮 Game"] = {
		{ monitor = "LEFT", increment = true, cmd = "steam" },
	},

	["📅 Meeting"] = {
		{ monitor = "PRIMARY", increment = true, cmd = "firefox https://calendar.google.com/" },
		{ monitor = "CENTER", increment = true, cmd = "firefox" },
	},

	["📊 System Monitor"] = {
		Config.apps.journal,
		Config.apps.btop,
	},

	["🛡️ System Update"] = {
		{ monitor = "LEFT", increment = true, cmd = "kitty -e sysup" },
		Config.apps.journal,
	},

	["💼 Work"] = {
		Config.apps.firefox_triple,
		tmuxifier("uphill", "CENTER"),
		tmuxifier("config", "RIGHT"),
		Config.apps.slack,
		Config.apps.email,
	},
}

return Config
