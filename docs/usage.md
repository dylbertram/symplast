# Using Symplast

Symplast is a menu-bar control panel for Mutagen. Mutagen performs the actual
file synchronization and continues running if you quit Symplast.

## Start a sync

1. Click the Symplast icon in the macOS menu bar.
2. Choose **New session**, enter a name, and select the local folder and target.
   A target can be another local folder, an SSH destination such as
   `user@example.com:/path/to/folder`, or a supported custom Mutagen URL.
3. Choose a sync mode and review its direction. **Two-way safe** is the default.
   **One-way replica** can overwrite or delete files on the target.
4. Optionally add ignore patterns, then choose **Create session**.

For SSH targets, use a key available through your SSH agent and configuration;
Symplast cannot prompt for passwords or key passphrases. See
[SSH authentication](authentication.md) if the connection does not start.

## Manage sessions

- Use the pause/play control on a session to pause or resume it.
- Open **⋯** for actions such as forcing a sync cycle, opening either folder,
  editing the definition, resetting sync history, or terminating the session.
- **Terminate** stops the live session but keeps its saved definition. Use
  **Start** to recreate it, or **Forget definition** to remove the saved entry.
- The menu-bar icon and session status indicate connection and synchronization
  problems. Open **Settings** to refresh the session list or check for a newer
  Symplast release.

## Settings and data

Settings lets you change the refresh interval, set the Mutagen executable path,
and start the Mutagen daemon automatically. The **With Mutagen** download
includes its own Mutagen executable; the smaller **Without Mutagen** download
uses an existing installation.

Symplast saves session definitions and preferences locally. It checks GitHub's
public release metadata at launch and when you choose **Check for Updates**;
it sends no session or folder information. Mutagen owns the sync state and
history; saved definitions are not backups. Avoid running incompatible Mutagen
versions against the same daemon. See the
[installation guide](installation.md) for download verification and uninstalling.
