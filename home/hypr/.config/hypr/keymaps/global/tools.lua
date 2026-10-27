-- The tool actions (zoom, screenshot, voice, passwords, overviews, pickers, HyprVim terminal and marks) bind their own
-- keys when these files load.
require("lib.act").load_defs({ "tools", "pickers" })
