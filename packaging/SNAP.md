# Publishing Disc Writer to the Snap Store

Snap name: `discwriter` (registered to the `dhivakar1010` account).

## Confinement

Strict, with `plugin: flutter` and the `gnome` extension, the same shape as
BranchPilot, which passes automated review and releases immediately. Do not
upload a classic-confinement build: classic always goes to manual review, and
a revision sitting in review blocks every later release of the snap until it
is rejected from the dashboard (see BranchPilot's `packaging/SNAP.md`).

What strict confinement means for Disc Writer:

* **xorriso ships inside the snap** (`stage-packages: xorriso`).
  `Xorriso.locate()` prefers `$SNAP/usr/bin/xorriso`.
* **Drive access needs a one-time connection.** The `optical-drive` plug
  declares `write: true` because burning writes to `/dev/sr*`. With that
  attribute the interface is not auto-connected:

  ```bash
  sudo snap connect discwriter:optical-drive
  ```

  The snap description says so, and so does the app's Disc info page when it
  runs as a snap and finds no drive.
* **Files**: `home` and `removable-media` cover picking sources and saving
  ISOs; hidden top-level directories in `$HOME` are not visible.

## Building

```bash
snapcraft pack --use-lxd
```

Produces `discwriter_0.1.0_amd64.snap` in the repository root. The part's
`override-pull` deletes any host `build/` directory first, because its
CMakeCache.txt names host paths and CMake refuses to reuse it.

## Smoke test before uploading

```bash
sudo snap install --dangerous ./discwriter_0.1.0_amd64.snap
sudo snap connect discwriter:optical-drive
discwriter
```

## Uploading

```bash
snapcraft upload --release=stable discwriter_0.1.0_amd64.snap
snapcraft status discwriter
```

`snapcraft status` must list a revision on `stable`. "This snap has no
released revisions" means nothing shipped.
