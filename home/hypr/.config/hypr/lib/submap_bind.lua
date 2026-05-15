-- home/hypr/.config/hypr/lib/submap_bind.lua

local Window = require("lib.window")

--- @class SubmapBind
--- @field run fun(key: string, cmd: string, desc: string) Bind a key that resets the active submap then runs a shell command
--- @field exec fun(key: string, fn: fun(), desc: string) Bind a key that resets the active submap then calls a Hyprland API function
--- @field focus_or_launch fun(key: string, opts: { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }, desc: string) Bind a key that focuses an existing window or launches the app, resetting the active submap
--- @field run_swap_submap fun(key: string, cmd: string, submap_name: string, desc: string) Bind a key that runs a shell command then enters a named submap
--- @field run_then fun(key: string, cmd: string, fn: fun(), desc: string) Bind a key that runs a shell command, calls a Lua callback, then resets the submap
--- @field reset fun() Reset to the default submap (exits any active submap)
--- @field bind fun(sm: SubmapEntry, fn?: fun()) Bind a submap entry key, optionally overriding the default activation action
--- @field set_escape fun(sm?: SubmapEntry) Register exit and catchall binds for a submap
local SubmapBind = {}

--- Bind a key that resets the active submap then runs a shell command.
--- @param key string
--- @param cmd string
--- @param desc string
SubmapBind.run = function(key, cmd, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    hl.dispatch(hl.dsp.submap("reset"))
  end, { description = desc })
end

--- Bind a key that resets the active submap then calls a Hyprland API function.
--- @param key string
--- @param fn fun()
--- @param desc string
SubmapBind.exec = function(key, fn, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(fn)
  end, { description = desc })
end

--- Bind a key that focuses an existing window or launches the app, resetting the active submap.
--- @param key string
--- @param opts { program: string, class?: string, title?: string, exclude_title?: string, cmd?: string }
--- @param desc string
SubmapBind.focus_or_launch = function(key, opts, desc)
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
SubmapBind.run_swap_submap = function(key, cmd, submap_name, desc)
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
SubmapBind.run_then = function(key, cmd, fn, desc)
  hl.bind(key, function()
    hl.dispatch(hl.dsp.exec_cmd(cmd))
    fn()
    hl.dispatch(hl.dsp.submap("reset"))
  end, { description = desc })
end

--- Reset to the default submap (exits any active submap).
SubmapBind.reset = function()
  hl.dispatch(hl.dsp.submap("reset"))
end

--- Bind a submap entry key, optionally overriding the default activation action.
--- @param sm SubmapEntry
--- @param fn fun()|nil Override action; if nil, activates the submap by name
SubmapBind.bind = function(sm, fn)
  hl.bind(sm.key, fn or hl.dsp.submap(sm.name), { description = "+" .. sm.name })
end

--- Register exit and catchall binds for a submap.
--- Escape/BackSpace always reset. Unbound keys: if sm is provided, re-enter it; otherwise exit.
--- @param sm SubmapEntry|nil If provided, catchall stays in this submap instead of exiting
SubmapBind.set_escape = function(sm)
  hl.bind("Escape", SubmapBind.reset)
  hl.bind("BackSpace", SubmapBind.reset)
  local catchall_opts = { release = true, ignore_mods = true }
  if sm then
    hl.bind("catchall", hl.dsp.submap(sm.name), catchall_opts)
  else
    hl.bind("catchall", SubmapBind.reset, catchall_opts)
  end
end

return SubmapBind
