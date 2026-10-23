-- init.lua
---@diagnostic disable: undefined-global, redundant-parameter

-- Plugins
-- Full border around the window; frame-border.lua is generated from the Quickshell screen frame (round -> "rounded")
-- into the same $XDG_CONFIG_HOME/yazi that scripts/frame-app-corners writes to.
local frame_ok, frame_border = pcall(function()
	local config = os.getenv("XDG_CONFIG_HOME")
	if not config or config == "" then
		config = os.getenv("HOME") .. "/.config"
	end
	return dofile(config .. "/yazi/frame-border.lua")
end)
require("full-border"):setup({
	-- Available values: "plain", "rounded"
	set = frame_ok and frame_border or "plain",
})

-- Fuse Archive
-- require("fuse-archive"):setup({
-- 	smart_enter = true,
-- 	mount_dir = "/tmp",
-- })

-- Folder Rules
require("folder-rules"):setup()

-- Git integration
require("git"):setup()
require("githead"):setup({
	branch_prefix = "on",
	branch_borders = "()",
	branch_symbol = " ",
	branch_color = "blue",
	remote_branch_color = "cyan",

	tag_symbol = "󰓼 ",
	tag_color = "magenta",
	commit_symbol = " ",
	commit_color = "bright magenta",
	stashes_symbol = " ",
	stashes_color = "red",
	state_symbol = "󱐋 ",
	state_color = "bright yellow",

	staged_symbol = " ",
	staged_color = "green",
	unstaged_symbol = " ",
	unstaged_color = "yellow",
	untracked_color = "bright blue",
	untracked_symbol = " ",
})

-- Relative Motion
require("relative-motions"):setup({
	show_numbers = "relative",
})

-- SSHFS
require("sshfs"):setup({
	enable_custom_hosts = false,
	-- mount_dir = os.getenv("HOME") .. "/mnt",
	-- default_mount_point = "root",
	sshfs_options = {
		"reconnect",
		"compression=yes",
		"cache_timeout=300",
		"ConnectTimeout=10",
		"dir_cache=no",
		"dcache_timeout=600",
	},
	global_paths = {
		"~/.config",
		"/var/www",
		-- "/srv",
		-- "/opt"
		"/var/log",
		"/etc",
		-- "/tmp",
		-- "/usr/local",
		-- "/data",
		-- "/var/lib",
	},
	host_paths = {
		-- Optionally define default mount paths for specific hosts
		["whatbox"] = {
			"~/files",
		},
	},
})

local steam_appid = require("steam-appid")

function Linemode:steam_appid()
	return steam_appid.linemode(self)
end

require("restore"):setup()

-- Show symlink in status bar
Status:children_add(function(self)
	local h = self._current.hovered
	if h and h.link_to then
		return " -> " .. tostring(h.link_to)
	else
		return ""
	end
end, 3300, Status.LEFT)

-- Show username and hostname in header
Header:children_add(function()
	if ya.target_family() ~= "unix" then
		return ""
	end
	return ui.Span(ya.user_name() .. "@" .. ya.host_name() .. ":"):fg("blue")
end, 500, Header.LEFT)

-- Hide preview in NVIM
-- if os.getenv("NVIM") then
-- 	require("toggle-pane"):entry("min-preview")
-- end
