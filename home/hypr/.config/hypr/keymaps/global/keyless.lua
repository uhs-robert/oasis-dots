-- The actions with no key: reachable only by id, from `hypr-act`, voice or the bar. Nothing else requires these files.
require("lib.act").load_defs({
  "notifications",
  "style",
  "lock",
  "power",
  "screenshot",
  "zoom",
  "overview",
  "settings",
  "launcher",
})
