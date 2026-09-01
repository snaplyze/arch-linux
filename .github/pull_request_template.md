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
- [ ] Two clean Arch builds and byte comparison, when package/repository behavior changes
- [ ] Signed repository/strict-client acceptance, when trust or publication changes
- [ ] Required QEMU scenarios and screenshots, when runtime behavior changes

List exact commands, versions, digests and evidence links below.

## Release impact

State the SemVer impact and whether documentation, package revisions, trust material, release assets
or acceptance evidence changes.
