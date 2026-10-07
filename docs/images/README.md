# README screenshots

These are captures of the actual SwiftUI interface with isolated example data.
No live Mutagen sessions are created or changed.

From the repository root, regenerate the source images:

```sh
bash scripts/preview-ui.sh .report/readme --public --native
```

The native popover capture requires macOS screen-recording permission and briefly
shows a preview window. Replace the public assets using this mapping:

| Generated image in `.report/readme/` | Public asset |
| --- | --- |
| `native-popover-dark.png` | `sessions.png` |
| `new-session-dark.png` | `new-session-dark.png` |
| `new-session-light.png` | `new-session-light.png` |
| `settings-dark.png` | `settings-dark.png` |
| `settings-light.png` | `settings-light.png` |

The README's Spotlight/Finder icon uses
[`Resources/AppIcon-1024.png`](../../Resources/AppIcon-1024.png) directly.
