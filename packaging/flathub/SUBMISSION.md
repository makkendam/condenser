# Flathub submission

Checklist and texts for submitting Condenser to Flathub
(<https://docs.flathub.org/docs/for-app-authors/submission>).

## Before submitting

1. Make the GitHub repository public.
2. Add a screenshot at `packaging/screenshots/editor.png`. Take it from the app at
   roughly 1600×1000, showing a session with a clip marked.
3. Tag the release and fill in the commit in `io.github.makkendam.Condenser.yml`:
   ```
   git tag v1.0.0 && git push origin v1.0.0
   git rev-parse v1.0.0
   ```
4. Lint locally:
   ```
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest packaging/flathub/io.github.makkendam.Condenser.yml
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder appstream packaging/linux/io.github.makkendam.Condenser.metainfo.xml
   ```
5. Fork <https://github.com/flathub/flathub>. Then open a PR against its `new-pr` branch
   that adds `io.github.makkendam.Condenser.yml` (this folder's manifest) at the root.

## Linter exception to request

`finish-args-flatpak-appdata-folder-com.valvesoftware.Steam-.local-share-Steam-ro-access`

> Condenser edits and exports Steam's game recordings. When Steam is installed as the
> Flatpak `com.valvesoftware.Steam`, those recordings and the Steam settings that point
> to them (`userdata/*/config/localconfig.vdf`) live in that app's data folder. The
> access is read-only, and limited to `.local/share/Steam`.

## Notes for reviewers

- This is a fork of Pineapple Steam Recording Exporter (`net.blumia.pineapple-steam-recording-exporter`,
  already on Flathub). Condenser has its own name, icon and focus: an editor for full
  background sessions with a zoomable timeline, previews, and GPU (VA-API) export to
  H.264/HEVC/AV1. The original author is credited in the app's About dialog, README and metainfo.
- FFmpeg comes from the KDE runtime, so no extra modules are needed.
- `xdg-videos` is read-write because Steam's recording folder defaults to `~/Videos/Steam recordings`
  when it is customized there, and exports are written to `~/Videos/Steam Recording Exports`.
