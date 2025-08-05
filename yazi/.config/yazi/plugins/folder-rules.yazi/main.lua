-- Folder Rules

SORT_OPTIONS = {
	default = { "alphabetical", reverse = false, dir_first = true },
	by_mtime = { "mtime", reverse = true, dir_first = false },
	by_mtime_dir_first = { "mtime", reverse = true, dir_first = true },
	by_name_case_sensitive = { "alphabetical", reverse = false, dir_first = true, sensitive = true },
	natural = { "natural", reverse = false, dir_first = true, translit = true },
}

-- Define sorting rules for specific folders.
-- Add new entries to this table to apply sorting rules to other folders.
-- The key is the name of the folder.
-- The value is a table with sorting options that ya.emit("sort", ...) accepts.
-- e.g. { "mtime", reverse = true, dir_first = false }
local SORT_FOLDERS = {
	-- By Mtime
	Downloads = SORT_OPTIONS.by_mtime,
	tmp = SORT_OPTIONS.by_mtime,
	log = SORT_OPTIONS.by_mtime,
	Screenshots = SORT_OPTIONS.by_mtime,
	Recordings = SORT_OPTIONS.by_mtime,
	Backups = SORT_OPTIONS.by_mtime,
	-- By Mtime Dir First
	Projects = SORT_OPTIONS.by_mtime_dir_first,
	Code = SORT_OPTIONS.by_mtime_dir_first,
	Repos = SORT_OPTIONS.by_mtime_dir_first,
	Clients = SORT_OPTIONS.by_mtime_dir_first,
	Contracts = SORT_OPTIONS.by_mtime_dir_first,
	-- By Name Case sensitive
	dotfiles = SORT_OPTIONS.by_name_case_sensitive,
	[".config"] = SORT_OPTIONS.by_name_case_sensitive,
	[".local/share"] = SORT_OPTIONS.by_name_case_sensitive,
	[".scripts"] = SORT_OPTIONS.by_name_case_sensitive,
	-- Media
	Videos = SORT_OPTIONS.natural,
	Pictures = SORT_OPTIONS.natural,
	Wallpapers = SORT_OPTIONS.natural,
	Fonts = SORT_OPTIONS.natural,
	Music = SORT_OPTIONS.natural,
	-- Docs
	Documents = SORT_OPTIONS.by_mtime,
	Notes = SORT_OPTIONS.by_mtime,
	Zettlekasten = SORT_OPTIONS.by_mtime,
}

-- Apply sorting rules based on the current directory
local function applySortRules()
	local cwd = cx.active.current.cwd

	-- Apply sort rules to current directory
	for folder, rule in pairs(SORT_FOLDERS) do
		if cwd:ends_with(folder) then
			ya.emit("sort", rule)
			return
		end
	end

	-- Apply default sort rule if no specifc rule found
	ya.emit("sort", SORT_OPTIONS.default)
end

-- Apply sorting rules every time the directory is changed
local function setup()
	ps.sub("cd", function()
		applySortRules()
	end)
end

return { setup = setup }
