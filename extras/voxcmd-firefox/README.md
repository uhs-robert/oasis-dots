# voxcmd Firefox extension

Lets voxcmd list and switch Firefox tabs by the tab itself, instantly, unloaded tabs included. It holds one native-messaging port to `~/.local/share/voxcmd/firefox-host` and answers three requests: `tabs` (every tab of every window), `activate` (select a tab, focus its window and put the caller's nonce in front of that window's title with `titlePreface`, so the compositor can tell the window from others showing the same title) and `clear_preface` (take the nonce back; the extension also does it after 10 s if the caller never does). `titlePreface` is part of `windows.update` and needed no permission beyond `tabs` in the Firefox versions I know; if yours refuses it, `activate` still switches the tab and voxcmd falls back to whichever Firefox window has focus. It opens no URLs, runs no scripts in pages and asks only for the `tabs` and `nativeMessaging` permissions. Without it voxcmd keeps switching through the address bar.

Private windows are invisible to it, as to any extension that is not allowed in them.

## Set up

1. Stow the `voxcmd` package.
2. Run `just firefox-extension`. It registers the native host (`~/.mozilla/native-messaging-hosts/voxcmd_firefox.json`), copies `extras/voxcmd-firefox.xpi` to `/usr/share/oasis-dots/voxcmd-firefox.xpi` and adds a `normal_installed` entry for `voxcmd@oasis-dots` to `/etc/firefox/policies/policies.json` (needs sudo; other policies in that file are kept). The installer does the same. Restart Firefox.

Firefox reads one policies file and does not merge: `/etc/firefox/policies/policies.json` wins over `/usr/lib/firefox/distribution/policies.json`, so the recipe refuses to run while the latter exists. `normal_installed` lets you disable or remove the add-on in `about:addons`.

To try it without signing, run `just firefox-host`, open `about:debugging`, This Firefox, Load Temporary Add-on, and pick `extras/voxcmd-firefox/manifest.json`; it is gone when Firefox quits.

## Sign it

Release Firefox loads only signed add-ons. `just sign-firefox-extension` signs the extension as unlisted on addons.mozilla.org (AMO API key from rbw) and writes `extras/voxcmd-firefox.xpi`, which is committed.

## Update

Raise `version` in `manifest.json` (AMO refuses a version it has already signed), run `just sign-firefox-extension`, commit the xpi, then rerun `just firefox-extension` to copy it into place. Firefox needs no `update_url`: at startup it re-fetches a policy `install_url`, skips the same-URL shortcut for `file:` URLs, and reinstalls unless the version is equal. So the new version arrives on the next Firefox restart.

## Remove

Delete the `voxcmd@oasis-dots` key from `ExtensionSettings` in `/etc/firefox/policies/policies.json`, or set its `installation_mode` to `"blocked"`. Then remove the add-on in `about:addons` (deleting the policy does not uninstall it), and `/usr/share/oasis-dots/voxcmd-firefox.xpi` if you like.
