---
id: keys
title: Keys
status: draft
prs: []
implements:
  - home/hypr/.config/hypr/keymaps
  - home/hypr/.config/hypr/lib/key
depends_on: [actions]
keys:
  - super+space
  - super+/
  - super+shift+/
  - shift+/
  - escape
---
# Keys

## What it is for
The owner drives the desktop from the keyboard. This spec says what pressing a key does: how keys are written, the leader modifier, shortcuts that work anywhere against submaps (a set of keys you enter and then press one at a time), how to leave a submap, how to find out what a key does, and how `custom/` replaces or adds keys. What a key runs is an action; the actions spec says what each action does, and a key row here only says "runs the action with that id". The table of every shipped key is generated into the keybinds guide (`docs/keybinds.md`), not repeated here.

## Requirements
- **KEYS-01** A key is written as zero or more modifiers and a key name joined by ` + `, for example `CTRL + SHIFT + ESCAPE`.
- **KEYS-02** One bind can list several keys; each of them does the same thing.
- **KEYS-03** Most global shortcuts are the leader modifier plus a key. The leader is `SUPER` unless the machine's profile sets another.
- **KEYS-04** Changing the leader moves every leader shortcut and every shipped key that enters a submap to the new modifier; none keeps the old one. A key you write out in full, such as `SUPER + SHIFT + N`, stays as written, so an entry key of your own follows the leader only if built with the leader helper.
- **KEYS-05** [gap: untested] A global shortcut acts the moment it is pressed, wherever the keyboard focus is, except while a submap is active.
- **KEYS-06** A submap's entry key switches the keyboard into that submap.
- **KEYS-07** [gap: untested] While a submap is active only its own keys act. A global shortcut still acts there only if it is marked to work in submaps.
- **KEYS-08** The media keys, the screenshot key and the keybind search key are marked to work in submaps.
- **KEYS-09** A bind of your own can be marked to work in submaps.
- **KEYS-10** The media keys also work on the lock screen, and the volume keys repeat while held.
- **KEYS-11** The global focus and move-window shortcuts work with both the letter key (H J K L) and the arrow key.
- **KEYS-12** Moving and resizing offer four step sizes on the same direction keys: the bare key, SHIFT for larger steps, CTRL for the finest, and CTRL + SHIFT for the largest. Held keys repeat.
- **KEYS-13** ESCAPE leaves a submap the way that submap is set up: out of every submap (the default), back one level, or into a named submap. A submap may have no ESCAPE.
- **KEYS-14** BACKSPACE returns to the submap you came from, or leaves every submap when there is none.
- **KEYS-15** In a one-shot submap, a bound key does its action and then leaves the submap, unless its row is marked to stay or the submap has no ESCAPE.
- **KEYS-16** In a one-shot submap, a key that is not bound just leaves the submap and does nothing else, unless the submap has no ESCAPE.
- **KEYS-17** In a stay-until-ESCAPE submap, a key that is not bound does nothing and is not passed on to the focused application.
- **KEYS-18** The leader modifier plus SPACE enters the Leader submap, a one-shot menu of pickers, voice commands, the start menu and settings.
- **KEYS-19** The leader modifier plus `/` opens the keybind search.
- **KEYS-20** [gap: untested] The keybind search lists every bind of the mode you are in, submaps first and marked with `+`, and running a choice does what the key would.
- **KEYS-21** [gap: untested] The leader modifier plus SHIFT plus `/` opens which-key from anywhere, listing the global binds or, inside a submap, that submap's.
- **KEYS-22** [gap: untested] Entering a submap shows its binds in which-key.
- **KEYS-23** SHIFT plus `/` in a submap hides or shows which-key without leaving it.
- **KEYS-24** The search and which-key show each bind's description. A bind with no description, such as the second spelling of a directional key, is not listed.
- **KEYS-25** [gap: untested] `custom/init.lua` runs after every shipped key is registered, so it can remove or replace any of them.
- **KEYS-26** [gap: untested] Binding a key that already has a bind keeps both; both run when it is pressed.
- **KEYS-27** Unbinding a key stops its bind from acting and reports how many binds it removed. It reports 0 when nothing matched.
- **KEYS-28** Unbinding matches a key whatever the case or spacing it was written with, so `super+h` finds `SUPER + H`.
- **KEYS-29** Unbinding a key from one named submap leaves the same key in every other submap and in the global map alone, and unbinding it without a submap name leaves the submaps alone.
- **KEYS-30** Unbinding with the leader form takes the key without its modifier and follows the leader.
- **KEYS-31** After a key is unbound, binding it again leaves exactly one live bind, the new one.
- **KEYS-32** Unbinding removes only binds made through the key helpers. A bind made any other way, including the Vim navigation layer's own, is left alone and not counted.
- **KEYS-33** Adding binds to a submap by name creates the submap if it does not exist and otherwise adds to it, so a key can be changed in one submap.
- **KEYS-34** A submap of your own is defined by a name, an entry key, a label, an ESCAPE behaviour, a one-shot or stay setting, and rows of key, action and description.
- **KEYS-35** A shipped keymap file that fails to load costs only its own keys. The others still load and one warning names the file.
- **KEYS-36** A shipped keymap file that fails partway leaves no stray keys in other submaps, and a submap whose setup failed has no entry key.
- **KEYS-37** A submap whose setup failed cannot be entered by any means: not by a key row, not by the submap-entering action.

## Look
Which-key lists a submap's binds as the keyboard enters it. The keybind search puts submaps first, each marked with a `+`.

## Not covered
- What each shipped key is bound to, and what each action does: the generated table in `docs/keybinds.md` and the actions spec.
- An empty leader: shipped submap entry keys are then written with a stray ` + `, so the setting is not supported.
- Mouse binds, and the direction-pair "diagonal" chords of the cursor and resize submaps.
- How which-key and the search are drawn, and the exact key names a keyboard produces.
- The Vim navigation layer's own keys.
- On Hyprland 0.56 and older an unbound key is disabled, not removed: it stops firing but still appears in search and which-key. From 0.57 it is removed. `custom/README.md` explains why.
- How unbinding is tracked, and the stubbed `hl` the tests use.
- Errors in a file of your own under `custom/` propagate like any other config error and are not caught.
