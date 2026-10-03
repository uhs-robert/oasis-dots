-- home/hypr/.config/hypr/lib/missing_repos.lua

--- Collects missing repo-backed parts and posts one notification naming them.
--- @class MissingRepos
local MissingRepos = {}

local missing = {}
local scheduled = false

--- Records a missing part and schedules a single notification.
--- @param what string Human name of the part that failed to load
MissingRepos.add = function(what)
  table.insert(missing, what)
  if scheduled then return end
  scheduled = true
  hl.timer(
    function()
      hl.notification.create({
        text = "Missing: " .. table.concat(missing, ", ") .. ". Run `just repos` in your dotfiles.",
        timeout = 15000,
      })
    end,
    { timeout = 2000, type = "oneshot" }
  )
end

return MissingRepos
