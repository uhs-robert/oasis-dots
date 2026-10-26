-- The actions with no key: reachable only by id, from `hypr-act`, voice or the bar. Nothing else requires these files.
for _, file in ipairs({
  "notifications",
  "style",
  "lock",
  "power",
  "screenshot",
  "zoom",
  "overview",
  "settings",
  "launcher",
}) do
  require("lib.actions.defs." .. file)
end
