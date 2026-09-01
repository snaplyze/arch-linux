# Contributing

Read [AGENTS.md](AGENTS.md) before changing code. Keep each change bounded, preserve the installer
and signing invariants, and update behavior-selected tests and current documentation together.

## Source workflow

```bash
git diff --check
bash tests/source-tests.sh
```

Do not commit generated `installer.conf`, logs, package artifacts, VM disks, firmware state,
acceptance evidence or secrets. A package-source change must update its committed `.SRCINFO` and all
reviewed hashes in the same change; never regenerate pins or trust inputs automatically.

A pull request should state the affected product invariant, the exact tests executed and any clean
Arch/QEMU/release acceptance still deferred. Passing tests from another tree do not transfer.
