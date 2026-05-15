-- home/hypr/.config/hypr/lib/submap_bind.lua

local Window = require("lib.window") ---@class Window

--- @class SubBind
local SubBind = {}

--- Bind a key that resets the active submap then runs a shell command.
--- @param key string
--- @param cmd string
--- @param desc string
SubBind.run = function(key, cmd, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    hl.dispatch(hl.dsp.submap("reset"))
  end, { description = desc })
end

--- Bind a key that resets the active submap then calls a Hyprland API function.
--- @param key string
--- @param fn fun()|HL.Dispatcher
--- @param desc string
SubBind.exec = function(key, fn, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(fn)
  end, { description = desc })
end

--- Bind a key that focuses an existing window or launches the app, resetting the active submap.
--- @param key string
--- @param opts { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }
--- @param desc string
SubBind.focus_or_launch = function(key, opts, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.submap("reset"))
    Window.focus_or_launch(opts)
  end, { description = desc })
end

--- Bind a key that runs a shell command then enters a named submap.
--- @param key string
--- @param cmd string
--- @param submap_name string
--- @param desc string
SubBind.run_then_swap_to = function(key, cmd, submap_name, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    hl.dispatch(hl.dsp.submap(submap_name))
  end, { description = desc })
end

--- Bind a key that runs a shell command, calls a Lua callback, then resets the submap.
--- @param key string
--- @param cmd string
--- @param fn fun()
--- @param desc string
SubBind.run_then_fn = function(key, cmd, fn, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    fn()
    hl.dispatch(hl.dsp.submap("reset"))
  end, { description = desc })
end

--- Bind a submap entry key, optionally overriding the key or activation action.
--- @param sm SubmapEntry
--- @param opts? { key?: string, fn?: fun() }
SubBind.swap_to = function(sm, opts)
  local key = (opts and opts.key) or sm.key
  local action = (opts and opts.fn) or hl.dsp.submap(sm.name)
  hl.bind(key, action, { description = "+" .. sm.name })
end

--- Bind Escape and BackSpace to reset the submap, plus a catchall policy.
--- By default unbound keys also exit; swallow_mispress=true swallows them instead.
--- @param opts? { swallow_mispress?: boolean }
SubBind.bind_exits = function(opts)
  local function reset() hl.dispatch(hl.dsp.submap("reset")) end
  hl.bind("Escape", reset)
  hl.bind("BackSpace", reset)
  local catchall_opts = { release = true, ignore_mods = true }
  local fn = (opts and opts.swallow_mispress) and hl.dsp.no_op() or reset
  hl.bind("catchall", fn, catchall_opts)
end

return SubBind
