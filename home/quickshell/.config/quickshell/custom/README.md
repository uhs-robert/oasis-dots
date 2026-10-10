# Custom config

This directory holds your own machine-local Quickshell config. Everything in it other than `README.md` and `.gitignore` is gitignored, so your files stay local and never show up in `git status`.

What the shell reads from here:

- `command-status.json`: the commands behind the `cmdstatus` bar module. See "Command status" in the Quickshell README for the format.

## Keeping your files

To track them and carry them between machines, keep them in a repo of your own and link each file in:

```bash
ln -s ~/my-dots/quickshell/custom/command-status.json ~/.config/quickshell/custom/command-status.json
```

Link files, not the `custom/` directory itself: this README and `.gitignore` are tracked here and must stay in place. `~/.config/quickshell` is a folded stow link into this repo, so stow from another repo cannot add files to it.
