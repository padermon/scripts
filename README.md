# RomM Favorites Export for R36S

A dependency-free macOS Bash script that exports favorite games from a [RomM](https://github.com/rommapp/romm) instance into an R36S, ArkOS, and EmulationStation-compatible directory structure.

The script creates a `gamelist.xml` for each system and can optionally download ROM files, covers, marquees, and videos.

## Features

- Exports only games marked as favorites in RomM
- Maps common RomM platform slugs to ArkOS system directories
- Downloads ROM files and all available RomM media
- Creates EmulationStation-compatible `gamelist.xml` files
- Optimizes the four core media slots for the Elementerial ArkOS theme
- Supports paginated RomM libraries
- Skips files that have already been downloaded
- Does not write credentials or export reports to the output directory
- Requires no Python packages or `jq`

## Requirements

- macOS
- Bash
- `curl`
- `osascript`
- RomM 5.x or a compatible API

`curl` and `osascript` are included with macOS. The script currently uses JavaScript for Automation through `osascript` to process RomM's JSON responses, so Linux is not currently supported.

## Installation

```bash
git clone git@github.com:padermon/scripts.git
cd scripts
chmod +x romm_favorites_r36s_export.sh
```

## Usage

```bash
./romm_favorites_r36s_export.sh \
  --romm https://romm.example.com \
  --username YOUR_USERNAME \
  --output ./r36s-export \
  --download-roms \
  --download-media
```

Export directly to a mounted EASYROMS partition:

```bash
./romm_favorites_r36s_export.sh \
  --romm https://romm.example.com \
  --username YOUR_USERNAME \
  --output /Volumes/EASYROMS \
  --download-roms \
  --download-media
```

## Authentication

By default, the script asks for the RomM password using a hidden prompt.

Alternatively, set the password for the current shell through `ROMM_PASSWORD`:

```bash
read -s ROMM_PASSWORD
export ROMM_PASSWORD
./romm_favorites_r36s_export.sh \
  --romm https://romm.example.com \
  --username YOUR_USERNAME \
  --output ./r36s-export \
  --download-roms \
  --download-media
unset ROMM_PASSWORD
```

The `--password` option is also supported, but is not recommended because command-line arguments can appear in shell history and process listings.

## Dry run

Use `--dry-run` to inspect the planned export without writing to the output directory:

```bash
./romm_favorites_r36s_export.sh \
  --romm https://romm.example.com \
  --username YOUR_USERNAME \
  --output ./r36s-export \
  --download-roms \
  --download-media \
  --dry-run
```

## Output structure

```text
r36s-export/
  gba/
    Game.gba
    gamelist.xml
    media/
      bezels/
      box2d/
      box2d-back/
      box2d-side/
      box3d/
      fanart/
      logos/
      marquees/
      manuals/
      miximages/
      miximages-v2/
      physical/
      screenshots/
      title-screens/
      videos/
      videos-normalized/
```

Only media types available for a game are written. File extensions are retained
from the source URL where possible.

## Elementerial media mapping

The script is optimized for
[Elementerial for ArkOS](https://github.com/giovaboy/es-theme-elementerial-arkos).
That theme directly uses four EmulationStation media fields in its Detailed,
Grid, Boxes, Video, and Elementflix views:

| Gamelist field | Elementerial usage | Selection priority |
| --- | --- | --- |
| `image` | Detailed view, Boxes view, Grid screenshot | `miximage_v2`, `miximage`, screenshot, large cover, `box2d`, `box3d` |
| `thumbnail` | Elementflix, Grid thumbnail | `box2d`, small cover, large cover, screenshot |
| `marquee` | Game logo and video snapshot | marquee, logo |
| `video` | Video view and Elementflix | `video_normalized`, video |

The selected core files reference the corresponding files in the full media
export, avoiding unnecessary duplicate downloads where possible.

For compatibility with other EmulationStation forks and library tools, the
generated gamelist also includes available extended fields such as `fanart`,
`manual`, `boxart`, `boxback`, `cartridge`, `screenshot`, `titleshot`, `wheel`,
`mix`, and `bezel`. ArkOS versions that do not use an extended field safely
ignore it.

## Supported RomM media

The exporter recognizes the following RomM media types:

- bezel
- box2d
- box2d back
- box2d side
- box3d
- miximage
- miximage v2
- physical media
- screenshot
- title screen
- marquee
- logo
- fanart
- video
- normalized video
- manual

Depending on the metadata available in RomM, each `gamelist.xml` entry can contain:

- ROM path and title
- Description
- Image and thumbnail
- Marquee
- Video
- Rating
- Release date
- Developer and publisher
- Genre and player count

The RomM favorite flag is used only to select which games are exported. The
exporter deliberately does not write `<favorite>true</favorite>` to the target
`gamelist.xml`, so favorites can be managed independently on the handheld.

## Options

```text
--romm URL          RomM instance URL, required
--username USER     RomM username, required
--password PASS     Password; use the prompt or ROMM_PASSWORD instead when possible
--output PATH       Output directory, required
--download-roms     Download ROM files
--download-media    Download all available RomM media
--dry-run           Show planned actions without writing to the output directory
-h, --help          Show help
```

## Security

- Do not commit passwords, API tokens, exported ROMs, or generated media.
- Prefer the hidden password prompt over `--password`.
- The password and access token are kept only for the lifetime of the process.
- Temporary API responses are removed automatically when the script exits.

Only export and use ROM files that you are legally permitted to access.
