# Publishing Disc Writer to the Snap Store

Snap name: `discwriter` (registered to the `dhivakar1010` account).

## Current state (2026-10-10)

**Revision 1 (0.1.0) is in manual review, not released.** The upload
returned:

```
Status: will need manual review
- human review required due to 'deny-connection' constraint (interface attributes)
```

The `write: true` attribute on `optical-drive` is what triggers it: the
base declaration denies connecting that plug unless the store grants it, so
every upload with it needs a reviewer. Without `write: true` the snap could
read discs but never burn one, so the attribute stays and the store has to
approve it. Ask in the forum's store-requests category, with the
justification below.

Until revision 1 is approved or rejected, **no later revision can be
released** (BranchPilot hit the same blocking behaviour). Do not upload
another revision expecting it to go out first.

Forum request text (category: store-requests):

> **discwriter: request for optical-drive `write: true`**
>
> Disc Writer (https://github.com/Dhiva-Labs/DiscWriter) is a CD/DVD/Blu-ray
> burner. Every job it performs (burning data discs and ISO images, erasing
> rewritable media, verifying burns) is done by the bundled xorriso writing
> to `/dev/sr*`, so it needs the optical-drive interface with `write: true`.
> Without write access the application cannot perform its core function. We
> are asking for installation to be allowed with the plug; manual connection
> (`snap connect discwriter:optical-drive`) is fine and is documented in the
> snap description and in the app itself. Revision 1 is waiting in review.

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

Produces `discwriter_0.1.0_amd64.snap` in the repository root (`..._arm64.snap` when
run on an arm64 machine: `architectures:` in `snap/snapcraft.yaml` builds on each
architecture it runs on). CI builds both and attaches them to a release; it never
uploads to the Store. The part's
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
snapcraft upload --release=stable discwriter_0.1.0_arm64.snap   # the arm64 build
snapcraft status discwriter
```

`snapcraft status` must list a revision on `stable`. "This snap has no
released revisions" means nothing shipped.
