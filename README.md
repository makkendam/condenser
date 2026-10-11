# Condenser

Condenser turns hours of Steam background recordings into short clips.

It opens on your most recent session in a big player. Mark a start and end on the timeline (or press `I` and `O`), hit Export, and get an MP4: either Steam's original stream without re-encoding, or H.264 encoded on the GPU (VAAPI) or CPU (libx264) so it plays everywhere.

## Why

Steam's own recording export on Linux only looks for an NVIDIA encoder when re-encoding, so exporting HEVC recordings fails on AMD and Intel GPUs, and H.264 exports are capped at 1920 pixels wide. Condenser does the export with FFmpeg instead.

## Features

- Sessions (Steam's background recordings) and saved clips in separate tabs
- Timeline with time marks and the time under the mouse, for finding moments in long sessions
- Export a part of a recording without saving a clip in Steam first
- Original stream copy, or H.264 on the GPU/CPU, capped at the recording's own bitrate
- Names for non-Steam game shortcuts (e.g. Battle.net) from `shortcuts.vdf`

## Building

Condenser is built as a Flatpak:

```sh
flatpak run org.flatpak.Builder --user --install --force-clean build packaging/flatpak/top.makkendam.Condenser.yml
```

## Credits

Condenser is based on [Pineapple Steam Recording Exporter](https://github.com/BLumia/pineapple-steam-recording-exporter) by Gary "BLumia" Wang.

## License

The source code of this project is licensed under [**GNU General Public License v3.0 only**](https://spdx.org/licenses/GPL-3.0-only.html) license. Individual files may have a different, but compatible license.
