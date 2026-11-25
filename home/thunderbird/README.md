# Thunderbird / Betterbird

This package holds `quicktext/quicktext.json`, the Quicktext add-on's templates. It is a tracked copy: paste it into the add-on's options page by hand, because the add-on does not read it from disk. Stow ignores the folder (`.stow-local-ignore`), so nothing from this package lands in `~`.

Keybindings come from the DesertBird add-on, installed by hand into the profile. The old tbkeys setup is gone; `migrate_retire_tbkeys` in `lib/install/migrate.sh` removes its root-owned files on existing machines.
