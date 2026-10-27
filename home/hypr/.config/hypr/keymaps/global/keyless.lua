-- The actions with no key: reachable only by id, from `hypr-act`, voice or the bar. A submap may require one of these
-- files again for its rows; Act.load_defs keeps a broken file from raising there too.
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
