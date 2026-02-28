# qutebrowser/.config/qutebrowser/config.py
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
from pathlib import Path

oasis_lagoon.setup(c, "lagoon", True)

# --- Globals ---
LEADER = "<Space>"
BW = "spawn --userscript qute-bitwarden --auto-lock 86400"
FIREFOX = "spawn --detach firefox"
YAZI = [
    "kitty",
    "--title",
    "qute-yazi",
    "-e",
    "yazi",
    "--chooser-file",
    "{}",
]
DEFAULT_SEARCH = "duck"
LAGOON_CSS = "~/.config/qutebrowser/solarized-everything-css/css/oasis_lagoon/oasis_lagoon-all-sites.css"
DESERT_CSS = "~/.config/qutebrowser/solarized-everything-css/css/oasis_desert/oasis_desert-all-sites.css"
GRUVBOX_CSS = (
    "~/.config/qutebrowser/solarized-everything-css/css/gruvbox/gruvbox-all-sites.css"
)
HINT_FOLLOW = "unique-match"
USER_SCRIPT_GLOB = f"file://{Path.home()}/.local/share/qutebrowser/userscripts/*"

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
    USER_SCRIPT_GLOB,
)
config.set(
    "content.local_content_can_access_file_urls",
    False,
    USER_SCRIPT_GLOB,
)
config.set("hints.auto_follow", f"{HINT_FOLLOW}")

# --- ISSUE: SUPRESS TRUSTEDHTML ERRORS ---
c.content.javascript.log_message.excludes.update(
    {
        "userscript:_qute_js": [
            "*requires 'TrustedHTML' assignment*",
            "*Failed to set the 'innerHTML' property*requires 'TrustedHTML' assignment*",
        ],
    }
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

## -- Hints --
### - Scroll -
c.hints.selectors["scroll"] = [
    '[style*="overflow: auto"]',
    '[style*="overflow:auto"]',
    '[style*="overflow: scroll"]',
    '[style*="overflow:scroll"]',
    '[class*="scroll"]',
    ".scroll",
    ".scrollable",
]

### - Focusable containers -
c.hints.selectors["focusbox"] = [
    "main",
    "article",
    "section",
    '[role="main"]',
    '[role="article"]',
    '[role="region"]',
    "[tabindex]",
    '[contenteditable="true"]',
]

### - Videos -
c.hints.selectors["video"] = [
    "video",
    '[role="application"] video',
    ".html5-video-player",
    "#movie_player",
    'iframe[src*="youtube.com/embed"]',
    'iframe[src*="player.vimeo.com"]',
]

### - Binds -
config.bind(";v", "hint video normal")
config.bind(";;", "hint focusbox normal")

#### Double Click Mode
RESET_HINT_FOLLOW = f"set hints.auto_follow {HINT_FOLLOW}"
ENABLE_DBL_CLICK = "set hints.auto_follow never"
config.bind(";D;", f"{ENABLE_DBL_CLICK} ;; hint --rapid focusbox tab-bg")
config.bind(";Df", f"{ENABLE_DBL_CLICK} ;; hint --rapid all tab-bg")
config.bind(";Ds", f"{ENABLE_DBL_CLICK} ;; hint --rapid scroll tab-bg")
config.bind("<Return>", "cmd-repeat 2 hint-follow", mode="hint")  # Double click
config.bind(
    "<Ctrl+Return>",
    f"cmd-repeat 2 hint-follow ;; mode-leave ;; {RESET_HINT_FOLLOW}",
    mode="hint",
)
config.bind("<Escape>", f"mode-leave ;; {RESET_HINT_FOLLOW}", mode="hint")

# --- Keybindings ---
## -- Go --
config.bind("gT", ":open -t translate.google.com/translate?sl=auto&tl=en-US&u={url}")
config.bind("gm", "cmd-set-text -s :tab-move ")
config.bind(
    ";<Space>i", "hint images run :open -t https://tineye.com/search?url={hint-url}"
)

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
config.bind("sr", "config-source")
config.bind("sR", "restart")
config.bind("sth", "set tabs.position left")
config.bind("stj", "set tabs.position bottom")
config.bind("stk", "set tabs.position top")
config.bind("stl", "set tabs.position right")

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


## -- Z --
config.bind("zb", "jseval -q document.activeElement && document.activeElement.blur()")
config.bind("zz", "jseval -q document.querySelector('body').click()")

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
config.bind(f"{LEADER}tl", f'config-cycle content.user_stylesheets {LAGOON_CSS} ""')
config.bind(f"{LEADER}tg", f'config-cycle content.user_stylesheets {GRUVBOX_CSS} ""')
config.bind(f"{LEADER}td", f'config-cycle content.user_stylesheets {DESERT_CSS} ""')
config.bind("td", "config-cycle colors.webpage.darkmode.enabled true false ;; reload")
for mode in ["true", "false"]:
    config.bind(f"t{mode[0]}", f"set -u {{url}} colors.webpage.darkmode.enabled {mode}")
    config.bind(
        "tD",
        "config-cycle -u {url} colors.webpage.darkmode.enabled true false ;; reload",
    )


## -- Devloper Tools --
config.bind(f"{LEADER}ws", "jseval -q --world main Logger.switch()")
config.bind(
    f"{LEADER}wi", "jseval -q --world main window.show_knack_id?.api?.toggleIds?.()"
)
config.bind(
    f"{LEADER}wh",
    "jseval -q --world main window.show_knack_id?.api?.toggleShowHidden?.()",
)

# --- File handler ---
config.set("fileselect.handler", "external")
c.fileselect.single_file.command = YAZI
c.fileselect.multiple_files.command = YAZI
c.fileselect.folder.command = YAZI

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
    "greasyfork": "https://greasyfork.org/en/scripts?q={}",
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

# --- Adblocking ---
c.content.blocking.enabled = True

## Uncomment this if you install python-adblock
# c.content.blocking.method = 'adblock'

## Use UBlock Origin Adblocking Lists
# c.content.blocking.adblock.lists = [
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/legacy.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters-2020.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters-2021.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters-2022.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters-2023.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/filters-2024.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/badware.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/privacy.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/badlists.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/annoyances.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/annoyances-cookies.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/annoyances-others.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/badlists.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/quick-fixes.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/resource-abuse.txt",
#         "https://github.com/uBlockOrigin/uAssets/raw/master/filters/unbreak.txt"]
