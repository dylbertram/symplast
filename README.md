# MutagenDock

A small macOS **menu bar** app that shows which folders are synced with
[Mutagen](https://mutagen.io/documentation/introduction/installation/), lets you
pause/resume them, add & save new sync sessions, and warns you when a session
goes disconnected.

It is a thin, native SwiftUI front-end over the `mutagen` CLI — it never touches
Mutagen's internals, so it stays compatible across Mutagen versions.

## Features

- **Menu bar icon** that reflects the overall health of your sessions
  (watching ●, syncing ↻, paused ⏸, disconnected ⚠). Shows the session count.
- **Live session list** with per-session status, local ⇄ remote paths and
  file/size counts, refreshed on a configurable interval.
- **Start / stop**: pause and resume any session inline.
- **Force sync** (`flush`) and **reset history** per session.
- **Disconnected monitoring**: unreachable endpoints are highlighted in red and
  the menu bar icon changes so you notice without opening the menu.
- **Create & save sessions**: pick a local folder plus an SSH target, a local
  folder, or a custom URL; choose a sync mode (each with an explanation,
  including a "two-way (remote wins)" option), ignore rules and VCS/build-output
  handling.
- **Edit sessions**: change a session's name, folders, mode or ignores; Mutagen
  has no in-place edit, so MutagenDock terminates and recreates it for you.
- **Saved definitions**: every session you create (and every existing session
  MutagenDock discovers) is remembered locally. Terminate a session and it moves
  to "Saved · not running" where you can start it again with one click.
- **Daemon handling**: detects when the Mutagen daemon isn't running and offers a
  one-click start (it is also started automatically on launch).

## Requirements

- macOS 14 or newer
- [Mutagen](https://mutagen.io/documentation/introduction/installation/) installed
  (`brew install mutagen`), plus `ssh` for remote targets
- Xcode command line tools / Swift toolchain to build

## Build & run

```sh
# build a debug/release .app bundle into ./build
./scripts/build-app.sh

# launch it
open build/MutagenDock.app
```

Or build, install to `/Applications`, and launch in one step:

```sh
./scripts/install.sh
```

Because the bundle is a menu bar–only app (`LSUIElement`), it has no Dock icon
and launches straight into the menu bar.

## Using it

- Click the menu bar icon to open the panel; **right-click** (or ⌃-click) it
  for a quick menu with **New session…**, **Open**, and **Quit**.
- Hover a row's **pause** button to stop watching; press **play** to resume.
- `⋯` on a row → **edit** the session, reveal the local folder, copy paths,
  reset history, or terminate.
- **New session** → fill in a name, local folder, target, mode and ignore rules.
- **Start** next to a saved definition recreates its Mutagen session.

## Configuration

Open **Settings** (gear icon) to:

- Override the `mutagen` executable path (auto-detected otherwise).
- Change the refresh interval (1–15 s).
- Toggle the session count in the menu bar.
- Toggle auto-starting the daemon on launch.

`mutagen` is located by checking Homebrew/system locations first, then falling
back to your login shell. This matters because apps launched from Finder do not
inherit your shell `PATH`; MutagenDock also repairs `PATH`, `HOME` and
`SSH_AUTH_SOCK` for the child process so SSH remotes keep working.

## How it works

| File | Responsibility |
| --- | --- |
| `Sources/MutagenDock/MutagenDockApp.swift` | `@main` app, `MenuBarExtra`, app delegate |
| `Services/MutagenClient.swift` | Finds & runs `mutagen`, parses JSON, builds commands |
| `Services/AppStore.swift` | Observable state, polling loop, actions, persistence |
| `Models/` | Session/endpoint models, sync state, saved definitions, settings |
| `Views/` | Menu bar label, panel, session rows, new-session form, settings |

Data comes from `mutagen sync list --template '{{json .}}'`. Actions map to
`mutagen sync pause|resume|flush|reset|terminate|create`. Saved definitions are
stored in `UserDefaults`.

## Notes & limitations

- Conflicts are surfaced via the session status; there is no dedicated conflict
  resolver UI yet.
- The SSH port is preserved when you create a session through the form; a
  session reconstructed automatically from an existing one uses the
  `user@host:path` form (Mutagen's default SSH port).
- Sessions are stored by Mutagen itself; "saving" here means MutagenDock
  remembers the *definition* so it can recreate a session you terminated.
