# RomM Favorites Export for R36S

A dependency-free macOS Bash script that exports favorite games from a [RomM](https://github.com/rommapp/romm) instance into an R36S, ArkOS, and EmulationStation-compatible directory structure.

The script creates a `gamelist.xml` for each system and can optionally download ROM files, covers, marquees, and videos.

## Features

- Exports only games marked as favorites in RomM
- Maps common RomM platform slugs to ArkOS system directories
- Downloads ROM files and available media
- Creates EmulationStation-compatible `gamelist.xml` files
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
      images/
        Game.png
      marquees/
        Game.png
      videos/
        Game.mp4
```

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
- Favorite status

## Options

```text
--romm URL          RomM instance URL, required
--username USER     RomM username, required
--password PASS     Password; use the prompt or ROMM_PASSWORD instead when possible
--output PATH       Output directory, required
--download-roms     Download ROM files
--download-media    Download images and videos
--dry-run           Show planned actions without writing to the output directory
-h, --help          Show help
```

## Security

- Do not commit passwords, API tokens, exported ROMs, or generated media.
- Prefer the hidden password prompt over `--password`.
- The password and access token are kept only for the lifetime of the process.
- Temporary API responses are removed automatically when the script exits.

Only export and use ROM files that you are legally permitted to access.
