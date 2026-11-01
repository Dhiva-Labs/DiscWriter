# Flatpak

`com.dhivalabs.discwriter.yml` builds the Disc Writer Flatpak bundle that CI
attaches to releases (`discwriter-<version>-x86_64.flatpak` and
`-aarch64.flatpak`).

## How CI builds it

The `flatpak` job in `.github/workflows/ci.yml` unpacks the installed tree of
the `.deb` built earlier in the same run into `packaging/flatpak/tree/` and
runs flatpak-builder on the manifest in the
`ghcr.io/flathub-infra/flatpak-github-actions:gnome-51` image, natively on an
x64 and an arm64 runner. The bundle therefore ships the same Flutter build as
the `.deb`, `.rpm`, Arch package and AppImage.

The manifest has two modules:

- **xorriso**: GNU xorriso, the upstream release that has libburn, libisofs
  and libisoburn built in, compiled from source. Disc Writer does all of its
  burning by running xorriso, and the GNOME runtime has none. The app looks
  for xorriso on `PATH`, which inside the sandbox finds `/app/bin/xorriso`.
- **discwriter**: the installed tree, with the desktop file and icons renamed
  to the app ID, and the AppStream metadata.

CI then installs the bundle and checks, inside the sandbox, that every ELF
file under `/app` finds its libraries (`ldd-check.sh`), that `xorriso` on
`PATH` is the bundled one, and that it burns and verifies an MD5-checked data
session on a file-backed drive (`stdio:`). Last, it starts the app under
Xvfb with `packaging/linux-distros/smoke.sh`, which waits for a painted
Flutter UI and for the app's own `xorriso -devices` drive scan.

To install the bundle (the GNOME 51 runtime comes from Flathub):

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./discwriter-0.1.1-x86_64.flatpak
flatpak run com.dhivalabs.discwriter
```

## Permissions

| Permission | Why |
|---|---|
| `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc`, `--device=dri` | display and GPU for the Flutter UI |
| `--device=all` | the optical drives (`/dev/sr*`, `/dev/sg*`); Flatpak has no narrower device permission |
| `--filesystem=home` | files and folders to burn, images to burn, and where ISO images are saved, from the file chooser and from drag and drop |
| `--filesystem=/media`, `/run/media`, `/mnt` | the same on USB drives and other mounted media, as the snap's `removable-media` plug |

There is no network access.

## What it can and cannot do

- **Burning needs drive access on the host.** `--device=all` makes the drive
  visible in the sandbox, but opening it still takes the same rights as
  outside: membership of the `cdrom` group, or the device access the desktop
  session gives the logged-in user. The sandbox adds no privileges.
- **Real drives are not exercised in CI.** GitHub's runners have no optical
  drive, so CI proves the bundled xorriso with a file-backed drive and proves
  that the app finds and runs it; burning to a physical disc from the Flatpak
  has to be tried on real hardware.
- Files outside the home directory and the mount points above are not
  visible to the app.

## Flathub

A Flathub submission would differ in two ways:

1. The `discwriter` module's `tree` directory source becomes an `archive`
   source pointing at the release `.deb` (or the release tarball) with its
   sha256, or the app is built from source with the Flutter SDK and every
   pub package listed as sources, since Flathub builds offline.
2. Flathub reviews `--device=all` and `--filesystem=home`; for a disc
   burner, the reasons are the table above.

Each release also needs a `<release>` line in
`com.dhivalabs.discwriter.metainfo.xml`.
