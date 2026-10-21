-- Runs vectors.tsv through the Lua validator Hyprland uses (Input.state() in config/input), under stock `lua`.
-- Each vector is written as a one-key input.json and accepted when the key survives; this mirrors run_js.js.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local hypr_dir = here .. "/../../../hypr/.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local state_home = io.popen("mktemp -d"):read("l")
local real_getenv = os.getenv
os.getenv = function(name) -- lib.state reads XDG_STATE_HOME, which stock Lua cannot set
  if name == "XDG_STATE_HOME" then return state_home end
  return real_getenv(name)
end
os.execute("mkdir -p '" .. state_home .. "/hypr'")

local Input = require("config.input")

local total, failed = 0, 0
for line in io.lines(here .. "/vectors.tsv") do
  if line ~= "" and line:sub(1, 1) ~= "#" then
    local key, raw, verdict, note = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    local file = assert(io.open(state_home .. "/hypr/input.json", "w"))
    file:write('{"' .. key .. '": ' .. raw .. "}")
    file:close()
    local accepted = Input.state()[key] ~= nil
    total = total + 1
    if accepted ~= (verdict == "accept") then
      failed = failed + 1
      print(("FAIL %s = %s (%s)\n  want: %s\n  got:  %s"):format(key, raw, note, verdict, accepted and "accept" or "reject"))
    end
  end
end

os.execute("rm -rf '" .. state_home .. "'")
print(("%d/%d passed"):format(total - failed, total))
os.exit(failed == 0 and 0 or 1)
