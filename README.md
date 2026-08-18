# Tridactyl Godmode

This installs a targeted Firefox AutoConfig hook that lets a normal Tridactyl
installation run on restricted web pages and internal documents. It does not
modify `omni.ja`, rebuild Firefox, alter the signed XPI, or install another copy
of Tridactyl.

## Security warning

This deliberately disables an important Firefox security boundary. AutoConfig
runs with browser-process privileges, and Tridactyl gains DOM access to pages
ordinary extensions cannot touch. Mozilla considers this dangerous. Use it
only on a Firefox installation and machine you control.

The optional chrome key handoff is more invasive: it sends a trusted copy of a
key pressed in Firefox UI into the selected page. Page JavaScript can observe
that key and may receive user activation. Do not enable it unless you accept
that risk, especially on untrusted pages.

## Supported setup

The default target is Firefox Developer Edition at:

```text
/usr/lib/firefox-developer-edition
```

The hook targets these exact, non-temporary extension IDs:

```text
tridactyl.vim@cmcaine.co.uk
tridactyl.vim.betas@cmcaine.co.uk
tridactyl.vim.betas.nonewtab@cmcaine.co.uk
```

The installer does not restrict Firefox versions. The runtime hook validates
the expected internal methods at startup and reports an error instead of
patching unknown structures. Firefox updates can still change behavior without
changing those method names, so use the runtime checks below after an update.

## Install

Close every Firefox process, then run:

```sh
./verify.sh
sudo ./install.sh
./verify.sh /usr/lib/firefox-developer-edition
```

Pass another native or extracted Firefox directory explicitly:

```sh
sudo ./install.sh /opt/firefox-developer-edition
./verify.sh /opt/firefox-developer-edition
```

Use `sudo` only when the Firefox directory is root-owned. Run the scripts as
your normal user for a user-owned portable extraction; the installer rejects a
mismatched effective user before creating lifecycle files.

`FIREFOX_DIR` can replace the argument for `install.sh` and `uninstall.sh`;
`verify.sh` requires an explicit path. The default is Arch Linux's Developer
Edition layout. Flatpak, Snap, and other read-only packages are unsupported.

The installer is idempotent and records checksums for safe upgrades and
uninstalls. It refuses to overwrite files changed outside the installer or an
AutoConfig preference found in the target's `defaults/pref` directory.

The installed files are:

```text
<firefox>/defaults/pref/tridactyl-godmode.js
<firefox>/tridactyl-godmode.cfg
<firefox>/tridactyl-godmode-key-handoff-child.sys.mjs
<firefox>/tridactyl-godmode.state
<firefox>/.tridactyl-godmode.lock
```

The hidden lock serializes lifecycle operations. Interrupted transactions are
rolled back automatically on the next install or uninstall.

Firefox package upgrades may remove unowned files. Re-run `install.sh` and
`verify.sh` after an upgrade, then repeat the runtime checks below.

## How it works

The default-preference file loads `tridactyl-godmode.cfg` without the AutoConfig
sandbox, before AddonManager starts extensions.

For an exact Tridactyl ID, the hook:

- marks only the live extension instance privileged;
- grants the live `mozillaAddons` permission;
- disables restricted-domain and quarantined-domain checks;
- adds internal origins to its host permissions and `<all_urls>` content script;
- retains Firefox's original privilege status during persistent permission
  bookkeeping;
- clears stale Tridactyl startup-cache data before manifest loading; and
- strips synthetic permissions from later manifest-cache writes.

The signed extension, ID, UUID, storage, and profile location stay unchanged.
AMO updates retain Firefox's normal signature checks.

## Optional key handoff

Chrome-to-page key handoff is installed but disabled by default. To try it:

1. Open `about:config`.
2. Set `tridactyl.godmode.chrome_key_handoff` to `true`.
3. Restart Firefox.

After an official Tridactyl instance starts, a key pressed while focus is in
the URL bar, tab strip, or other main browser chrome is consumed. Firefox
focuses the selected tab and sends a trusted copy of that first `keydown` to
the top-level document. Subsequent physical keys go directly to the page's
restored focus and Tridactyl. Modifier-only keydowns remain in browser chrome,
so a chord is handed off when its non-modifier key arrives.

`Ctrl+Shift+F12` toggles handoff for the current window while browser chrome
has focus. The toggle is not persistent; setting the preference to `false` and
restarting disables the feature completely. Handoff also stops intercepting if
the last targeted Tridactyl instance shuts down, and it disables itself for a
window if the content actor fails.

Composition, dead-key, `Process`, and AltGraph input is left in browser chrome
because it cannot be reconstructed reliably. The relay synthesizes one trusted
`keydown`, not native keyboard input, and does not recreate IME processing,
`keypress`, text insertion, or transient keyboard state. The selected page can
observe the relayed key and any physical keys typed after focus moves.

## Internal schemes

The runtime hook adds these match patterns:

| Pattern | Expected behavior |
| --- | --- |
| `about:*` | The reliable core for tab-loaded Firefox pages. |
| `chrome://*/*` | Works only for navigable chrome documents loaded as tab content. It cannot reach the browser toolbar or main window. |
| `resource://*/*` | Works only for navigable resource documents in a compatible content process. Most resources are not documents. |
| `view-source:*` | Accepted by Firefox's matcher but historically unsupported for content-script execution. Treat it as experimental. |

`<all_urls>` still covers ordinary URLs. Separate restrictions can affect file
and opaque documents. Internal-page scripts receive an isolated extension
sandbox, not Firefox's system principal, and cannot reach the main browser UI.

## Verify Firefox

After restarting Firefox Developer Edition, open the Browser Console and run:

```js
const { ExtensionParent } = ChromeUtils.importESModule(
  "resource://gre/modules/ExtensionParent.sys.mjs"
);
const ids = new Set([
  "tridactyl.vim@cmcaine.co.uk",
  "tridactyl.vim.betas@cmcaine.co.uk",
  "tridactyl.vim.betas.nonewtab@cmcaine.co.uk",
]);
const extension = [...ExtensionParent.GlobalManager.extensionMap.values()].find(
  candidate => ids.has(candidate.id)
);
({
  id: extension?.id,
  isPrivileged: extension?.isPrivileged,
  permissions: [...(extension?.permissions || [])],
  origins: extension?.allowedOrigins.patterns.map(pattern => pattern.pattern),
  matches: extension?.contentScripts.flatMap(script => script.matches),
});
```

Expected results include `isPrivileged: true`, `mozillaAddons`, and all four
internal match patterns. The Browser Console also logs messages prefixed with
`[tridactyl-godmode]`.

Then test Tridactyl on:

```text
https://addons.mozilla.org/
about:robots
about:license
about:support
about:config
chrome://global/content/aboutAbout.html
resource://gre-resources/hiddenWindow.html
view-source:https://example.com/
```

The final three are implementation-dependent smoke tests, not guaranteed
capabilities. Press `:` or inspect the page for `#cmdline_iframe` to confirm
that Tridactyl's content script loaded.

## Uninstall

Close every Firefox process, then run:

```sh
sudo ./uninstall.sh
```

Pass the Firefox directory for a non-default installation.

Restart Firefox. No profile data or Tridactyl files need to be restored. The
uninstaller validates the recorded installation checksums before removing
anything and refuses to delete locally modified files. The loader preference is
removed and verified before the privileged config file.

## Development checks

Run `./verify.sh`.

Node.js is needed only for these source checks, not for installation or
installed-file verification. The checks cover JavaScript and shell syntax, a
startup model for targeted privilege and cache sanitation, cross-realm Firefox
objects, failure rollback, temporary and unrelated extension isolation, hook
idempotence, optional key handoff and actor dispatch, transactional upgrades
and legacy-state migration, crash recovery, conflict detection, unsafe-path
rejection, and uninstall recovery.

The logo uses elements designed by Jake Beazley, Vecteezy.com, and David A Se.
