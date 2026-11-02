# Making a release

Keep the bundle ID `local.frizurd.menu-veil-prototype` and use the same Developer ID team across releases. Changing either can invalidate users' existing menu-detection permission. Do not use ad hoc signing for public releases.

## One-time credentials

Run `bash scripts/setup-notarization.sh` in your own terminal. It stores Apple's credential in Keychain as profile `menu-veil`. The ignored `.release.env` contains only the profile name and public signing identity fingerprint. Never commit passwords, private keys, exported signing certificates, or Keychain files.

## Build and notarize

```sh
set -a
source .release.env
set +a
zsh scripts/release.sh
```

The script tests the visibility safeguards, builds both CPU architectures, signs with hardened runtime and timestamp, submits to Apple, staples and validates the ticket, and checks Gatekeeper. It then creates `build/Menu-Veil-0.2.1.zip` and a cask with its exact SHA-256. A notarization failure stops the script; do not publish the archive anyway.

The app has no automatic updater. Users receive updates through Homebrew or by replacing the app with a signed release.

## Publish

1. Commit the source for the version and tag that exact commit.
2. Upload the final ZIP to the matching GitHub release.
3. Put `build/menu-veil.rb` in `frizurd/homebrew-tap/Casks/` and push it.
4. Verify the release download's checksum, run Homebrew's cask style/audit checks, and test an install.
5. Only then mark the README's Homebrew command as live.

Do not use `--no-quarantine`, strip downloaded files' quarantine attributes, or instruct users to disable Gatekeeper. If Gatekeeper rejects the release, fix signing or notarization.

For local diagnostics, launch the installed app with `--diagnostics`. It writes state changes to `$TMPDIR/menu-veil-status.json`; production launches don't write that file. `--allow-development` permits a deliberate development session outside Applications, but must not be used in install instructions.
