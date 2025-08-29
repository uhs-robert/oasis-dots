-- init.lua
-- Plugins
-- Full border around the window
require("full-border"):setup({
	-- Available values: ui.Border.PLAIN, ui.Border.ROUNDED
	type = ui.Border.PLAIN,
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
th.git = th.git or {}
th.git.modified = ui.Style():fg("blue")
th.git.deleted = ui.Style():fg("red"):bold()
th.git.modified_sign = "M"
th.git.deleted_sign = "D"

-- SSHFS
require("sshfs"):setup({
	enable_custom_hosts = false,
	sshfs_options = {
		"reconnect",
		"compression=yes",
		"cache_timeout=300",
		"ConnectTimeout=10",
		"dir_cache=no",
		"dcache_timeout=600",
	},
})

require("restore"):setup()

require("recycle-bin"):setup()

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
if os.getenv("NVIM") then
	require("toggle-pane"):entry("min-preview")
end
