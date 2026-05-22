# relative-motions.yazi (fork)

<!--toc:start-->

- [relative-motions.yazi (fork)](#relative-motionsyazi-fork)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [Usage](#usage)
  <!--toc:end-->

A [Yazi](https://github.com/sxyazi/yazi) plugin based about vim motions.

https://github.com/dedukun/relative-motions.yazi/assets/25795432/04fb186a-5efe-442d-8d7b-2dccb6eee408

**(Moved) Smart truncate feature** (moved to [smart-truncate.yazi](https://github.com/boydaihungst/smart-truncate.yazi/tree/master?tab=readme-ov-file#for-relative-motions-my-fork-plugin-users))

![(Moved) Smart truncate](https://i.imgur.com/P8WKB4B.png)

## Requirements

- [Yazi](https://github.com/sxyazi/yazi) >= v25.5.31
- [Smart-truncate.yazi](https://github.com/boydaihungst/smart-truncate.yazi): If you want to use smart truncate feature. Which is now disabled by default.

## Installation

```sh
ya pkg add boydaihungst/relative-motions
```

## Configuration

If you want to use the numbers directly to start a motion add this to your `keymap.toml`:

<details>

```toml
[[mgr.prepend_keymap]]
on = [ "1" ]
run = "plugin relative-motions -- 1"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "2" ]
run = "plugin relative-motions -- 2"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "3" ]
run = "plugin relative-motions -- 3"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "4" ]
run = "plugin relative-motions -- 4"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "5" ]
run = "plugin relative-motions -- 5"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "6" ]
run = "plugin relative-motions -- 6"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "7" ]
run = "plugin relative-motions -- 7"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "8" ]
run = "plugin relative-motions -- 8"
desc = "Move in relative steps"

[[mgr.prepend_keymap]]
on = [ "9" ]
run = "plugin relative-motions -- 9"
desc = "Move in relative steps"
```

</details>

Alternatively you can use a key to trigger a new motion without any initial value, for that add the following in `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on = [ "m" ]
run = "plugin relative-motions"
desc = "Trigger a new relative motion"
```

---

Additionally there are a couple of initial configurations that can be given to the plugin's `setup` function:

| Configuration               | Values                                                                    | Default | Description                                                                                                                        |
| --------------------------- | ------------------------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `show_numbers`              | `relative`, `absolute`, `relative_absolute` or `none`                     | `none`  | Shows relative or absolute numbers before the file icon                                                                            |
| `show_motion`               | `true` or `false`                                                         | `false` | Shows current motion in Status bar                                                                                                 |
| `only_motions`              | `true` or `false`                                                         | `false` | If true, only the motion movements will be enabled, i.e., the commands for delete, cut, yank and visual selection will be disabled |
| `smart_truncate` (new)      | `true` or `false`                                                         | `false` | Truncate filename/folder and symlink, but keep extension. i.e, `long_named_file….mkv`                                              |
| `line_numbers_styles` (new) | `{hovered = ui.Style():fg("#61afef"), normal = ui.Style():fg("#494D56")}` | none    | Set styles for hovered file/folder or normal file/folder                                                                           |

If you want, for example, to enable relative numbers as well as to show the motion in the status bar,
add the following to Yazi's `init.lua`, i.e. `~/.config/yazi/init.lua`:

```lua
-- ~/.config/yazi/init.lua
require("relative-motions"):setup({ show_numbers="relative", show_motion = true })
```

> [!NOTE]
> The `show_numbers` and `show_motion` functionalities overwrite [`Current:render`](https://github.com/sxyazi/yazi/blob/43b5ae0e6cc5c8ee96462651f01d78a0d98077fc/yazi-plugin/preset/components/current.lua#L26)
> and [`Status:children_render`](https://github.com/sxyazi/yazi/blob/43b5ae0e6cc5c8ee96462651f01d78a0d98077fc/yazi-plugin/preset/components/status.lua#L172) respectively.
> If you have custom implementations for any of this functions
> you can add the provided `Entity:number` and `Status:motion` to your implementations, just check [here](https://github.com/dedukun/relative-motions.yazi/blob/main/init.lua#L126) how we are doing things.

## Usage

This plugin adds the some basic vim motions like `3k`, `12j`, `10gg`, etc.
The following table show all the available motions:

| Command        | Description         |
| -------------- | ------------------- |
| `j`/`<Down>`   | Move `n` lines down |
| `k`/`<Up>`     | Move `n` lines up   |
| `gj`/`g<Down>` | Go `n` lines down   |
| `gk`/`g<Up>`   | Go `n` lines up     |
| `gg`           | Go to line          |

Furthermore, the following operations were also added:

| Command | Description   |
| ------- | ------------- |
| `v`     | visual select |
| `y`     | Yank          |
| `x`     | Cut           |
| `d`     | Delete motion |

This however must be followed by a direction, which can be `j`/`<Down>`, `k`/`<Up>` or repeating the command key,
which will operate from the cursor down, e.g. `2yy` will copy two files.

Finally, we also support some tab operations:

| Command | Description                          |
| ------- | ------------------------------------ |
| `t`     | create `n` tabs                      |
| `H`     | Move `n` tabs left                   |
| `L`     | Move `n` tabs right                  |
| `gt`    | Go to the `n` tab                    |
| `w`     | Close tab `n`                        |
| `W`     | Close `n` tabs right                 |
| `<`     | Swap current tab with `n` tabs left  |
| `>`     | Swap current tab with `n` tabs right |
| `~`     | Swap current tab with tab `n`        |
