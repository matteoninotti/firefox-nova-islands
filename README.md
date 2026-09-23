# firefox-nova-islands

Bring back the **floating islands** look of Firefox's Nova redesign: gaps between the toolbar, the sidebar and the page, with rounded, bordered blocks.

Firefox 156 removed those gaps ([bug 2062351](https://bugzilla.mozilla.org/show_bug.cgi?id=2062351), [bug 2063294](https://bugzilla.mozilla.org/show_bug.cgi?id=2063294)), and no setting brings them back. This repo re-applies the CSS rules those patches deleted. They're copied from the Firefox 155.0.1 source code and loaded through `userChrome.css`.

## What you get

It behaves the same as Firefox 155:

| Window state | Result |
|---|---|
| Normal window | 4px gap around the window edge and between the toolbar, sidebar and page. All blocks are rounded and bordered. |
| Maximized | No gap at the window edge. The gaps between the toolbar, sidebar and page stay. |
| Fullscreen | No outer gap and no rounding. The gap between the sidebar and the page stays. |
| Compact density | 2px gaps. Only the inner corner is rounded. |

It also covers split view, docked DevTools, the expand-on-hover sidebar, sidebar on the right, customize mode, and themes.

It only does something when Nova is on. Nova is on by default from Firefox 157. On Firefox 156, turn it on by setting `browser.nova.enabled` to `true` in `about:config`.

## Install

Close Firefox first, or restart it afterwards.

### macOS / Linux

```sh
git clone https://github.com/matteoninotti/firefox-nova-islands.git
cd firefox-nova-islands
./install.sh
```

Or, without cloning:

```sh
curl -fsSL https://raw.githubusercontent.com/matteoninotti/firefox-nova-islands/main/install.sh | bash
```

### Windows (PowerShell)

Download and unzip the repo (**Code → Download ZIP**), then run this in that folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

### What the installer does

The installer lists your Firefox profiles, suggests the default one, and then:

1. backs up `chrome/userChrome.css` and `user.js` into `nova-islands-backup-<date>/` inside the profile
2. copies `nova-islands.css` into the profile's `chrome/` folder
3. adds `@import url("nova-islands.css");` as the first line of `chrome/userChrome.css`, creating the file if needed and keeping your existing styles
4. adds `toolkit.legacyUserProfileCustomizations.stylesheets = true` to `user.js`, which is what makes Firefox load `userChrome.css`

To pick a profile yourself, run `./install.sh --profile "<profile folder>"` or `.\install.ps1 -ProfilePath "<profile folder>"`. You can find the folder in `about:profiles`.

### Manual install

1. Open `about:config` and set `toolkit.legacyUserProfileCustomizations.stylesheets` to `true`.
2. Open `about:profiles` and click **Open Folder** (Show in Finder on macOS) next to your profile's root directory.
3. Create a `chrome` folder there if there isn't one, and copy `nova-islands.css` into it.
4. In `chrome/userChrome.css` (create it if needed), add this as the **first** line:
   ```css
   @import url("nova-islands.css");
   ```
5. Restart Firefox.

## Uninstall

```sh
./install.sh --uninstall
```
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

To uninstall by hand, delete `chrome/nova-islands.css` and remove the `@import` line from `chrome/userChrome.css`.

## Betterfox / arkenfox users

Their updaters replace `user.js` on every update, which removes the setting the installer added. Add this line to your `user-overrides.js` so it survives updates:

```js
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
```

## Compatibility

| Firefox | Status |
|---|---|
| 156.0 on macOS 15 | An earlier, macOS-only version of this CSS was tested with vertical tabs, sidebar, split view and DevTools. This version adds compact mode, expand-on-hover and 157 support, and hasn't been checked in the browser yet. |
| 157 (beta 4) | Checked against the source code. The selectors and the corner-size variable it relies on are handled. |
| Windows, Linux | Not tested. The rules are the same as Firefox 155's, and corner sizes come from Firefox itself. Please open an issue if something looks off. |
| `install.sh` | Tested on macOS (bash 3.2) with test profiles: install, re-install, uninstall, profile picker. |
| `install.ps1` | Not tested on Windows. Please report problems. |

Firefox changes its interface code often, so a future release can break this. If it does, please open an issue.

## License

[MPL-2.0](LICENSE). The CSS is based on Firefox source code, which is under the same license.
