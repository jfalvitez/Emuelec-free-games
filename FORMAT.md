# List format

Each console has one file named `<system>.jsonl`, where `<system>` is the EmuELEC folder name
(for example `atari5200.jsonl`). One game per line, written as JSON. Lines that start with `#` are ignored.

```json
{"label": "Game name", "system": "atari2600", "url": "https://direct.link/to/the/game/file", "source": "where it comes from", "author": "who made it", "size": 12345}
```

| Field | Required | Meaning |
|---|---|---|
| `label` | yes | Name shown in the menu. |
| `system` | yes | EmuELEC folder name. It must match the file name. |
| `url` | one of `url` / `page` | Direct link to the game file (`.zip` or a ROM). Only `http://` and `https://` links work. |
| `page` | one of `url` / `page` | A page that contains a `download_file/<number>` link (used for Zophar's Domain). |
| `size` | no | Size in bytes. If it is missing, the device measures it the first time. |
| `source` | no | Where the game is hosted. |
| `author` | no | Who made it. |

Rules
- Only free, public-domain or homebrew games whose author allows sharing. No commercial ROMs, no ROM hacks of commercial games.
- A `.zip` must contain a file type that the console accepts (listed in the first lines of each list file).
- No comma after the last field, and no empty lines inside a JSON line.

Not available on purpose: `ports`, `setup`, `mplayer`, `karaoke`, `imageviewer` (they run scripts or are not games),
and `apple2` / `fmtowns` (they only accept command files).
