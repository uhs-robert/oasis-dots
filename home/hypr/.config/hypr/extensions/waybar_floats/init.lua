-- home/hypr/.config/hypr/extensions/waybar_floats/init.lua
-- Generic float-at-cursor launcher for waybar popups with toggle support.
-- Call via: hyprctl eval 'waybar_float("CMD", W, "class")'

--- @param cmd string  shell command to dispatch
--- @param w integer|nil  window width; h is computed as 60% of monitor height
--- @param class string|nil  window class; when provided, clicking again toggles close
function _G.waybar_float(cmd, w, class)
  if class then
    for _, win in ipairs(hl.get_windows()) do
      if win.class == class then
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. win.address }))
        return
      end
    end
  end

  local pos = hl.get_cursor_pos()
  local mon = hl.get_monitor_at_cursor()
  local logical_w = math.floor(mon.width / mon.scale)
  local logical_h = math.floor(mon.height / mon.scale)
  local h = w and math.floor(logical_h * 0.6) or nil
  local lx = math.floor(pos.x) - mon.x
  local ly = math.floor(pos.y) - mon.y
  local my = ly + 32
  local mx

  if w and h then
    local raw = lx - math.floor(w / 2)
    mx = math.max(10, math.min(raw, logical_w - w - 10))
  else
    mx = math.max(10, lx)
  end

  local rules = "float;rounding 12;move " .. mx .. " " .. my
  if w and h then rules = "float;rounding 6;size " .. w .. " " .. h .. ";move " .. mx .. " " .. my end

  hl.dispatch(hl.dsp.exec_cmd("[" .. rules .. "] " .. cmd))
end
