-- home/hypr/.config/hypr/lib/bind.lua

local Config = require("config") --- @class Config

local LEADER = Config.leader
local ENABLE_VIM = Config.vim_mode

--- @class Bind
local Bind = {}

--- @class DirEntry
--- @field vim string   Vim-style key (H/J/K/L)
--- @field arrow string Arrow key name
--- @field dir string   Direction code (l/r/u/d)
--- @field label string Human label (Left/Right/Up/Down)

local DIR_INPUT = {
  { vim = "H", arrow = "Left", dir = "l", label = "Left" },
  { vim = "L", arrow = "Right", dir = "r", label = "Right" },
  { vim = "K", arrow = "Up", dir = "u", label = "Up" },
  { vim = "J", arrow = "Down", dir = "d", label = "Down" },
}

--- Bind a dispatcher for every direction. desc_prefix .. d.label fills the description.
--- Config.vim_mode gates hjkl; arrow keys always register.
--- @param mods string
--- @param make_dsp fun(d: DirEntry): any
--- @param desc_prefix? string
--- @param opts? table|fun(d: DirEntry): table
local function bind_dir_inputs(mods, make_dsp, desc_prefix, opts)
  for _, d in ipairs(DIR_INPUT) do
    local flags = type(opts) == "function" and opts(d) or {}
    if type(opts) == "table" then
      for k, v in pairs(opts) do
        flags[k] = v
      end
    end
    if desc_prefix then flags.description = desc_prefix .. d.label end
    if ENABLE_VIM then hl.bind(mods .. " + " .. d.vim, make_dsp(d), flags) end
    hl.bind(mods .. " + " .. d.arrow, make_dsp(d), flags)
  end
end

---@param keys string  Key combo appended to LEADER (e.g. "SHIFT + T")
---@param dispatcher any  Dispatcher value or zero-arg function
---@param opts? table
Bind.leader = function(keys, dispatcher, opts) hl.bind(LEADER .. " + " .. keys, dispatcher, opts) end

---@param keys string  Full key combo (no LEADER prefix)
---@param script string  Shell command to exec
---@param opts? table|string  Table or shorthand desc string
Bind.cmd = function(keys, script, opts)
  if type(opts) == "string" then opts = { desc = opts } end
  hl.bind(keys, hl.dsp.exec_cmd(script), opts --[[@as HL.BindOptions?]])
end

---@param keys string  Key combo appended to LEADER
---@param script string  Shell command to exec
---@param opts? table|string  Table or shorthand desc string
Bind.leader_cmd = function(keys, script, opts)
  if type(opts) == "string" then opts = { desc = opts } end
  Bind.leader(keys, hl.dsp.exec_cmd(script), opts --[[@as HL.BindOptions?]])
end

---@param mods string  Full modifier string (e.g. "SUPER + CTRL")
---@param make_dsp fun(d: DirEntry): any  Returns a dispatcher for each DIR_INPUT entry
---@param desc_prefix? string  Prepended to d.label; omit to set desc via opts
---@param opts? table|fun(d: DirEntry): table  Shared opts table, or per-direction opts factory
Bind.dir = function(mods, make_dsp, desc_prefix, opts) bind_dir_inputs(mods, make_dsp, desc_prefix, opts) end

---@param keys string  Key combo appended to LEADER (use "" for bare LEADER)
---@param make_dsp fun(d: DirEntry): any  Returns a dispatcher for each DIR_INPUT entry
---@param desc_prefix? string  Prepended to d.label; omit to set desc via opts
---@param opts? table|fun(d: DirEntry): table  Shared opts table, or per-direction opts factory
Bind.leader_dir = function(keys, make_dsp, desc_prefix, opts)
  bind_dir_inputs(LEADER .. (keys ~= "" and " + " .. keys or ""), make_dsp, desc_prefix, opts)
end

return Bind
