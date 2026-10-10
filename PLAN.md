# Disc Writer — plan

## v0.1 (done)

- [x] xorriso runner with packet output, severity parsing, SIGINT cancel
- [x] Drive discovery (`-devices`) with a sysfs fallback that flags
      permission problems
- [x] Media detection (`-toc`): profile, blank/appendable/closed, sessions,
      free blocks, volume id
- [x] Data disc projects: drag-and-drop, add files/folders, rename, unique
      root names, background size measurement, capacity bar
- [x] Exact pre-burn size check (`-print_size` + `-rollback_end`)
- [x] Burn project: fresh session or append (`-dev`), close/leave open,
      erase-first, speed with per-media unit suffix, simulate
- [x] Verify: session MD5 (`-check_md5`) for projects, byte-for-byte
      compare for images
- [x] Save as ISO (`-as mkisofs`, Joliet + Rock Ridge + ISO level 3)
- [x] Burn image (`-as cdrecord`)
- [x] Quick/full erase
- [x] Image file as drive (`stdio:`), used to rehearse burns and for testing
- [x] Unit, xorriso end-to-end and UI integration tests

## v0.1.0 release (done)

- [x] App icon, desktop entry
- [x] Snap (`discwriter`, strict, bundled xorriso, `optical-drive` write plug)
- [x] `.deb` and Launchpad PPA source package (`ppa:dhiva-labs/apps`)
- [x] GitHub Actions CI and GitHub release

## Next

- [ ] **Media change detection**: watch udev / `/sys/block/srN` events so
      inserting a disc refreshes without the refresh button
- [ ] **Audio CD**: WAV/FLAC tracks via `cdrskin` (xorriso doesn't write
      audio), with track list, gaps and CD-Text
- [ ] **Copy disc**: read to a temporary ISO (`-check_media` / `dd`) and
      burn it, with a single-drive swap prompt
- [ ] **Folder tree editing**: nested folders on the disc, not only
      root-level entries
- [ ] **Bootable images from a project**: El Torito boot image selection
- [ ] **Recent projects**: save/load project files (`.discproj` JSON)
- [ ] AppStream metadata
