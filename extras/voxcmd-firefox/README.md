# voxcmd Firefox extension

Lets voxcmd list and switch Firefox tabs by the tab itself, instantly, unloaded tabs included. It holds one native-messaging port to `~/.local/share/voxcmd/firefox-host` and answers three requests: `tabs` (every tab of every window), `activate` (select a tab, focus its window and put the caller's nonce in front of that window's title with `titlePreface`, so the compositor can tell the window from others showing the same title) and `clear_preface` (take the nonce back; the extension also does it after 10 s if the caller never does). `titlePreface` is part of `windows.update` and needed no permission beyond `tabs` in the Firefox versions I know; if yours refuses it, `activate` still switches the tab and voxcmd falls back to whichever Firefox window has focus. It opens no URLs, runs no scripts in pages and asks only for the `tabs` and `nativeMessaging` permissions. Without it voxcmd keeps switching through the address bar.

Private windows are invisible to it, as to any extension that is not allowed in them.

## Set up

1. Stow the `voxcmd` package, then run `just firefox-host` once to register the native host (`~/.mozilla/native-messaging-hosts/voxcmd_firefox.json`).
2. Open `about:debugging`, This Firefox, Load Temporary Add-on, and pick `extras/voxcmd-firefox/manifest.json`. A temporary add-on is gone when Firefox quits.

## Sign it to keep it

Firefox release builds load only signed add-ons permanently. Self-distribute it with an unlisted signature (needs AMO API keys from addons.mozilla.org):

```
web-ext sign --channel=unlisted --source-dir extras/voxcmd-firefox \
  --api-key "$AMO_JWT_ISSUER" --api-secret "$AMO_JWT_SECRET"
```

Open the resulting `.xpi` in Firefox to install it.
