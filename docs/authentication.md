# SSH authentication

Symplast does not implement SSH itself. Mutagen delegates every connection to
your system's OpenSSH client, so the same `~/.ssh/config`, keys, `known_hosts`
and agent that your terminal uses are what Match. This document explains how the
app wires that up, why authentication can fail, and how to make it reliable.

## How the app runs SSH

Mutagen's daemon spawns `ssh` (and `scp`) with the environment the app gave it
when it started the daemon. A menu-bar app launched from Finder/Spotlight does
**not** inherit the environment you see in Terminal, so Symplast rebuilds the
important parts before launching any `mutagen` command
(`Sources/Symplast/Services/MutagenClient.swift`):

- `PATH` — common Homebrew/local/bin locations are prepended.
- `HOME` — set explicitly.
- `SSH_AUTH_SOCK` — resolved in this order:
  1. the app's own environment (when launched from a terminal),
  2. the **login shell's** value (`zsh -lc`), if the socket exists,
  3. launchd's system agent.

Step 2 is the important one: GUI launches otherwise get launchd's system agent,
which usually holds **no identities**, while your real agent (Bitwarden,
1Password, etc.) is configured in your shell profile.

> The daemon is long-lived and inherits the environment of whatever started it.
> If your agent socket changes (for example a password-manager restart), the
> running daemon keeps the old socket. Run `mutagen daemon stop` in Terminal, then
> use **Start daemon** in the app to relaunch it with the current environment.

## The one hard limitation: passphrase prompts

Mutagen redirects SSH prompts (passphrases, passwords, host-key confirmation) to
its `sync create` / `resume` / `reset` commands, which normally prompt on the
**terminal**. A menu-bar app has no terminal, so Mutagen cannot ask you for a
secret, and the process can sit waiting.

Symplast handles this in three ways:

- **It stops at the prompt.** Password and key-passphrase prompts are detected
  while `create`, `resume` and `reset` run. The command stops immediately rather
  than repeatedly submitting an empty password. Password-only authentication is
  not supported; load an unlocked key in your SSH agent and retry.
- **It stops failed retries.** Mutagen's reported authentication errors mark the
  affected session disconnected immediately, and the session is paused to stop
  the daemon retrying. The error remains visible; use **Resume** after fixing
  your credentials. Healthy sessions are not affected.
- **It refuses to hang.** Every `mutagen` invocation also has a watchdog (30 s
  default) for other stalls. Authentication errors are shown as a compact summary,
  with the original details available in the tooltip.

Because the app cannot prompt, an SSH key must satisfy one of these:

- it has **no passphrase**, or
- it is **loaded in an SSH agent** the app can reach.

A session that stays unconnected for more than ~10 seconds is shown as
**Disconnected** rather than **Connecting**, because Mutagen retries a failing
connection indefinitely and keeps reporting a `connecting-*` status.

## Recommended setups (macOS)

### Password-manager agent (recommended)

Bitwarden and 1Password both provide an SSH agent and put `SSH_AUTH_SOCK` in your
shell profile, which Symplast reads. In the app, open **Settings → SSH
authentication** to confirm the agent path is your password manager's socket, not
`/var/run/…/Listeners`.

### macOS built-in agent + Keychain

```sh
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add to `~/.ssh/config` so new shells (and the app) reuse it:

```
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
```

### Verify before blaming the app

```sh
ssh-add -l                 # is your key loaded?
ssh admin@your-host true   # does non-interactive auth actually work?
```

If `ssh-add -l` reports "Could not open a connection to your authentication
agent", the agent is not running — start/unlock it, or the app will not be able
to authenticate either.

## Other failure modes

- **Host key not known.** The first connection to a new host asks
  `Are you sure you want to continue connecting?`. The app cannot answer, so the
  connection fails. Connect once from Terminal (or `ssh-keyscan host >> ~/.ssh/known_hosts`)
  to record it.
- **Wrong user or port.** Symplast's reconstructed targets do not keep a custom
  port; set it explicitly or use a `~/.ssh/config` `Host` alias.
- **Agent locked.** If your password manager locks, its socket stays but has no
  usable keys → `Permission denied (publickey)`. Unlock it and retry.
- **Multiple agents.** Only one `SSH_AUTH_SOCK` is used. The Settings readout
  shows which one.

## Not implemented (possible future work)

A native passphrase dialog would require running `mutagen` under a pseudo-terminal
and presenting a secure prompt when Mutagen asks for a secret. It is not built
today; agent-based auth is the supported path.
