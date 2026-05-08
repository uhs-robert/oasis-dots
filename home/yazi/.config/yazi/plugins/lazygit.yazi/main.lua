-- yazi/.config/yazi/plugins/lazygit.yazi/main.lua
local M = {}

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end

	local content = f:read("*a")
	f:close()

	content = content:gsub("%z", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if content == "" then
		return nil
	end

	return content
end

local function exists_dir(path)
	local status = Command("test"):arg({ "-d", path }):status()

	return status and status.success
end

function M:entry()
	local cwd = tostring(cx.active.current.cwd)
	local tmp = os.tmpname()

	local permit = ui.hide()

	local child, err = Command("lazygit")
		:cwd(cwd)
		:env("YAZI_LG_CWD_FILE", tmp)
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:spawn()

	if not child then
		permit:drop()
		ya.notify({
			title = "lazygit-cd",
			content = tostring(err),
			timeout = 5,
			level = "error",
		})
		return
	end

	child:wait()
	permit:drop()

	local target = read_file(tmp)
	os.remove(tmp)

	if target and exists_dir(target) then
		ya.emit("cd", { target, raw = true })
	end
end

return M
