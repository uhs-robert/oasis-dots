# qutebrowser/.config/qutebrowser/config.py
# config.py
########################################################################
#                                                                      #
#     ██████╗ ██╗   ██╗████████╗███████╗                               #
#    ██╔═══██╗██║   ██║╚══██╔══╝██╔════╝                               #
#    ██║   ██║██║   ██║   ██║   █████╗                                 #
#    ██║▄▄ ██║██║   ██║   ██║   ██╔══╝                                 #
#    ╚██████╔╝╚██████╔╝   ██║   ███████╗                               #
#     ╚══▀▀═╝  ╚═════╝    ╚═╝   ╚══════╝                               #
#                                                                      #
#    ██████╗ ██████╗  ██████╗ ██╗    ██╗███████╗███████╗██████╗        #
#    ██╔══██╗██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔════╝██╔══██╗       #
#    ██████╔╝██████╔╝██║   ██║██║ █╗ ██║███████╗█████╗  ██████╔╝       #
#    ██╔══██╗██╔══██╗██║   ██║██║███╗██║╚════██║██╔══╝  ██╔══██╗       #
#    ██████╔╝██║  ██║╚██████╔╝╚███╔███╔╝███████║███████╗██║  ██║       #
#    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝ ╚══════╝╚══════╝╚═╝  ╚═╝       #
#                                                                      #
########################################################################
# flake8: noqa: F821
# pyright: reportUndefinedVariable=false

import oasis_lagoon

oasis_lagoon.setup(c, "lagoon", True)

# --- Globals ---
LEADER = "<Space>"
BW = "spawn --userscript qute-bitwarden --auto-lock 86400"
FIREFOX = "spawn --detach firefox"
DEFAULT_SEARCH = "duck"
LAGOOON_CSS = "~/.config/qutebrowser/solarized-everything-css/css/oasis_lagoon/oasis_lagoon-all-sites.css"
GRUVBOX_CSS = (
    "~/.config/qutebrowser/solarized-everything-css/css/gruvbox/gruvbox-all-sites.css"
)

# --- Config ---
config.load_autoconfig(True)
config.set("content.cookies.accept", "all", "chrome-devtools://*")
config.set("content.cookies.accept", "all", "devtools://*")
config.set("content.headers.accept_language", "", "https://matchmaker.krunker.io/*")
config.set(
    "content.headers.user_agent",
    "Mozilla/5.0 ({os_info}; rv:136.0) Gecko/20100101 Firefox/139.0",
    "https://accounts.google.com/*",
)
config.set("content.images", True, "chrome-devtools://*")
config.set("content.images", True, "devtools://*")
config.set("content.javascript.enabled", True, "chrome-devtools://*")
config.set("content.javascript.enabled", True, "devtools://*")
config.set("content.javascript.enabled", True, "chrome://*/*")
config.set("content.javascript.enabled", True, "qute://*/*")
config.set("content.javascript.clipboard", "access")
config.set(
    "content.local_content_can_access_remote_urls",
    True,
    "file:///home/USER/.local/share/qutebrowser/userscripts/*",
)
config.set(
    "content.local_content_can_access_file_urls",
    False,
    "file:///home/USER/.local/share/qutebrowser/userscripts/*",
)

# --- Editor ---
c.editor.command = [
    "kitty",
    "--single-instance",
    "--wait-for-single-instance-window-close",
    "-T",
    "auxiliary text edit",
    "-e",
    "nvim",
    "+call cursor({line}, {column})",
    "+startinsert",
    "{file}",
]

# --- Basics ---
c.auto_save.session = True
c.hints.chars = "asdfghjklqwertyuiopzxcvbnm"
c.content.autoplay = False
c.downloads.location.directory = "~/Downloads"
c.tabs.position = "top"
c.statusbar.show = "in-mode"
c.tabs.show = "multiple"
c.fonts.default_family = "Maple Mono NF"
c.fonts.default_size = "11pt"
c.fonts.statusbar = '11pt "ProFont IIx Nerd Font Mono"'
c.fonts.debug_console = '11pt "ProFont IIx Nerd Font Mono"'
c.fonts.messages.error = '11pt "ProFont IIx Nerd Font Mono"'
c.fonts.messages.info = '11pt "ProFont IIx Nerd Font Mono"'
c.fonts.messages.warning = '11pt "ProFont IIx Nerd Font Mono"'
c.qt.args = ["blink-settings=preferredColorScheme=1"]
# c.spellcheck.languages = ["en-US"]


# --- Keybindings ---
## -- Delete --
config.unbind("d")
config.bind("dd", "tab-close")
config.bind("db", "cmd-set-text -s :quickmark-del ")
config.bind("dB", "cmd-set-text -s :bookmark-del ")
config.bind("dD", "cmd-set-text -s :download-delete ")
config.bind("dc", "cmd-set-text -s :download-clear")
config.bind("ds", "cmd-set-text -s :session-delete")

## -- Session --
config.bind("sg", "greasemonkey-reload")
config.bind("su", "adblock-update")
config.bind("se", "config-edit")
config.bind("sc", "clear-messages")
config.bind("sr", "restart")

## -- Window/Dev --
config.bind("wd", "cmd-set-text -s :download-open")
config.bind("wj", "cmd-set-text -s :jseval")

## -- Ctrl --
config.bind("<Ctrl+c>", "fake-key <Escape>")  # Send escape
config.bind("<Ctrl+Return>", "fake-key <Return>")  # Send escape
config.bind("<Ctrl+j>", "scroll-px 0 200")
config.bind("<Ctrl+k>", "scroll-px 0 -200")
config.bind("<Ctrl-E>", "config-cycle tabs.show always never")
config.bind("<Ctrl+Shift+i>", "devtools")

## -- Leader --
config.bind(f"{LEADER}{LEADER}", f"cmd-set-text -s :open {DEFAULT_SEARCH} ")
config.bind(f"{LEADER}F", "cmd-set-text -s :open -t ")  # open in new tab
config.bind(f"{LEADER}r", "reload")
config.bind(f"{LEADER}q", "quit")
config.bind(f"{LEADER}F", f"{FIREFOX} --new-tab {{url}}")  # Reopen in FF
config.bind(f"{LEADER}f", f"hint links {FIREFOX} --new-tab {{hint - url}}")  # Hint FF

## -- Login management --
config.bind(f"{LEADER}ll", BW)
config.bind(f"{LEADER}lu", f"{BW} --username-only")
config.bind(f"{LEADER}lp", f"{BW} --password-only")
config.bind(f"{LEADER}lt", f"{BW} --totp")
config.bind(f"{LEADER}lT", f"{BW} --totp-only")

## -- MPV workflow (official FAQ pattern) --
config.bind(f"{LEADER}m", "ispawn mpv {url}")
config.bind(f"{LEADER}M", "hint links spawn mpv {hint-url}")

## -- Toggles --
config.bind(f"{LEADER}tn", f'config-cycle content.user_stylesheets {LAGOON_CSS} ""')
config.bind(f"{LEADER}tN", f'config-cycle content.user_stylesheets {GRUVBOX_CSS} ""')
config.bind("td", "config-cycle colors.webpage.darkmode.enabled true false ;; reload")
for mode in ["true", "false"]:
    config.bind(f"t{mode[0]}", f"set -u {{url}} colors.webpage.darkmode.enabled {mode}")
    config.bind(
        "tD",
        "config-cycle -u {url} colors.webpage.darkmode.enabled true false ;; reload",
    )

## -- Hints --
### - Scroll (Targets scrollable elements, useful to escape inputs for scrolling) -
c.hints.selectors["scroll"] = [
    '[style*="overflow: auto"]',
    '[style*="overflow:auto"]',
    '[style*="overflow: scroll"]',
    '[style*="overflow:scroll"]',
    '[class*="scroll"]',
    ".scroll",
    ".scrollable",
]

### - Binds -
config.bind(";;", "hint scroll normal")

# --- File handler ---
config.set("fileselect.handler", "external")
config.set(
    "fileselect.single_file.command",
    ["env", "GTK_THEME=Breeze-Dark:dark", "zenity", "--file-selection"],
)
config.set(
    "fileselect.multiple_files.command",
    ["env", "GTK_THEME=Breeze-Dark:dark", "zenity", "--file-selection", "--multiple"],
)

# --- Custom Search Engines ---
c.url.searchengines = {
    "DEFAULT": "https://duckduckgo.com/?q={}",
    "1337": "https://1337x.to/search/{}/1/",
    "arch": "https://wiki.archlinux.org/index.php?search={}",
    "amazon": "https://www.amazon.com/s?k={}",
    "brave": "https://search.brave.com/search?q={}",
    "gpt": "https://chatgpt.com/?q={}",
    "calendar": "https://calendar.google.com/calendar/u/0/r/search?q={}",
    "commons": "https://ccsearch.creativecommons.org/?search_fields=title&search_fields=creator&search_fields=tags&search={}",
    "crates": "https://crates.io/search?q={}",
    "duck": "https://duckduckgo.com/?q={}",
    "define": "http://www.merriam-webster.com/dictionary/{}",
    "sitedown": "https://www.isitdownrightnow.com/{}",
    "drive": "https://drive.google.com/drive/search?q={}",
    "gmail": "https://mail.google.com/mail/u/0/#search/{}",
    "fedora": "https://packages.fedoraproject.org/search?query={}",
    "flathub": "https://flathub.org/apps/search?q={}",
    "google": "https://www.google.com/search?q={}",
    "github": "https://github.com/search?q={}",
    "image": "https://www.google.com/search?tbm=isch&q={}",
    "lastyear": "https://www.google.com/search?hl=en&tbo=1&tbs=qdr:y&q={}",
    "lastmonth": "https://www.google.com/search?hl=en&tbo=1&tbs=qdr:m&q={}",
    "lastweek": "https://www.google.com/search?hl=en&tbo=1&tbs=qdr:w&q={}",
    "lastday": "https://www.google.com/search?hl=en&tbo=1&tbs=qdr:d&q={}",
    "lasthour": "https://www.google.com/search?hl=en&tbo=1&tbs=qdr:h&q={}",
    "maps": "http//maps.google.com/maps?f=q&source=s_q&hl=en&q=from+my+home+address+to+{}",
    "hackernews": "https://www.hnsearch.com/search#request/submissions&q={}",
    "imdb": "https://www.imdb.com/find?s=all&q={}",
    "mdn": "https://developer.mozilla.org/en-US/search?q={}",
    "npm": "https://www.npmjs.com/search?q={}",
    "proton": "https://www.protondb.com/search?q={}",
    "reddit": "https://www.reddit.com/search/?q={}",
    "redditgoogle": "https://www.google.com/search?q=site:reddit.com+{}",
    "rubygems": "https://rubygems.org/search?query={}",
    "this": "javascript:location='https://www.google.com/search?num=100&q=site:'+escape(location.hostname)+'+{}",
    "stackoverflow": "https://stackoverflow.com/search?q={}",
    "steam": "https://store.steampowered.com/search?term={}",
    "synonym": "https://www.thesaurus.com/browse/{}",
    "translate": "https://translate.google.com/?sl=auto&tl=en&text={}",
    "urbandictionary": "https://www.urbandictionary.com/define.php?term={}",
    "wikipedia": "https://www.wikipedia.org/w/index.php?search={}",
    "wolframalpha": "https://www.wolframalpha.com/input/?i={}",
    "youtube": "https://www.youtube.com/results?search_query={}",
}
