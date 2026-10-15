# Changelog

## 0.1.1 - 2026-10-16

### Added
- Linux arm64 builds: `discwriter-0.1.1-linux-arm64.tar.gz`, `discwriter_0.1.1_arm64.deb` and `discwriter_0.1.1_arm64.snap`, next to the x64 ones. The snap bundles `xorriso` for arm64 as well.
- CI builds, tests and packages Disc Writer on x64 and arm64 runners, including the xorriso end-to-end tests, and smoke-runs the installed package.
- The release job attaches the tarball, `.deb` and snap of both architectures to a published release and adds their checksums to `SHA256SUMS`. Files the release already has are left untouched.

### Changed
- `packaging/build_deb.sh` takes the architecture from the build machine instead of assuming amd64, and `packaging/build_tarball.sh` builds the portable tarball the same way.

No application code changed since 0.1.0.

## 0.1.0 - 2026-10-10

First release: data discs with multi-session, verification, burn image, save as ISO, erase and simulation, as x64 tarball, `.deb` and snap.
