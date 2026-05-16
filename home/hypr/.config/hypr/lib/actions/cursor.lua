--- Cursor actions: pointer movement, scrolling, clicking, key dispatch via wlrctl/hyprctl.

--- @class CursorActions
local Cursor = {}

--- Cursor movement factory for Direction.speed_binds.
--- @param amount number  Pixels to move per trigger
--- @return DirActions
function Cursor.move(amount)
  return {
    left  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move -" .. amount .. " 0")) end,
    right = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move "  .. amount .. " 0")) end,
    up    = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move 0 -" .. amount)) end,
    down  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer move 0 "  .. amount)) end,
  }
end

--- Scroll action factory. Returns up/down/left/right actions at the given step size.
--- @param step number
--- @return { up: fun(), down: fun(), left: fun(), right: fun() }
function Cursor.scroll(step)
  return {
    up    = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll "  .. step .. " 0")) end,
    down  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll -" .. step .. " 0")) end,
    left  = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll 0 -" .. step)) end,
    right = function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer scroll 0 "  .. step)) end,
  }
end

--- @return fun()
function Cursor.click_left()
  return function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer click left")) end
end

--- @return fun()
function Cursor.click_middle()
  return function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer click middle")) end
end

--- @return fun()
function Cursor.click_right()
  return function() hl.dispatch(hl.dsp.exec_cmd("wlrctl pointer click right")) end
end

--- Send a key shortcut to the active window via hyprctl sendshortcut.
--- @param key string  Key name, e.g. "LEFT", "prior", "next"
--- @return fun()
function Cursor.send_key(key)
  return function()
    hl.dispatch(hl.dsp.exec_cmd("hyprctl dispatch sendshortcut , " .. key .. ", activewindow"))
  end
end

return Cursor
