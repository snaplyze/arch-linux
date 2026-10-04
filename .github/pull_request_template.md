# Pull request

## Intent

Describe the user-visible result and why this is the smallest appropriate change.

## Safety and compatibility

Describe disk, sudoers, AUR ownership, GNOME/Stock fallback, package ownership, signatures and trust
effects. State “none” only after checking each relevant boundary.

## Validation

- [ ] Exact head SHA checked out in CI
- [ ] Syntax, version, static and function checks
- [ ] ShellCheck and `git diff --check`
- [ ] Documentation structure and links
- [ ] Secret and unsupported-source scans
- [ ] Canonical clean Arch build and independent verification, when package/repository behavior changes
- [ ] Advisory A+B byte-comparison result recorded separately, when run
- [ ] Signed repository/strict-client acceptance, when trust or publication changes
- [ ] Required functional QEMU scenarios, when runtime behavior changes; screenshots are optional diagnostics

List exact commands, versions, digests and evidence links below.

## Release impact

State the SemVer impact and whether documentation, package revisions, trust material, release assets
or acceptance evidence changes.
