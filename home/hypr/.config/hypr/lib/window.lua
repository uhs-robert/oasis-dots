-- home/hypr/.config/hypr/new/lib/window.lua
-- Focus-or-launch: find an existing Hyprland window or open the app.

local Window = {}

--- Return the address of the first client matching the given criteria.
--- @param class string Window class to match exactly
--- @param title string|nil Exact title or title-prefix match (prefix followed by space)
--- @param exclude_title string|nil Skip windows whose title starts with this string
--- @return string|nil
local function find(class, title, exclude_title)
  for _, c in ipairs(hl.get_windows()) do
    local ok = c.class == class
    if ok and title then ok = c.title == title or string.find(c.title, title .. " ", 1, true) == 1 end
    if ok and exclude_title then ok = string.find(c.title, exclude_title, 1, true) ~= 1 end
    if ok then return c.address end
  end
  return nil
end

--- Focus an existing window matching opts, or launch the app if none found.
--- @param opts { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }
function Window.focus_or_launch(opts)
  local class = opts.class or opts.program
  local address = find(class, opts.title, opts.exclude_title)
  if address then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
  else
    hl.dispatch(hl.dsp.exec_cmd(opts.cmd or opts.program))
  end
end

return Window
