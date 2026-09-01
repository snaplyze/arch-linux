# Advisory maintenance

Maintenance detects drift; it does not change source, accepted hashes, pins, keys or releases.

## Accepted Arch ISO

`maintenance/accepted-arch-iso.json` records the reviewed official x86_64 ISO. The detector validates
the exact official Arch API source and can compare current metadata without modifying accepted
state:

```bash
python3 maintenance/check-arch-iso.py
```

Updating accepted ISO state is a separate human-reviewed task. At minimum, a new ISO requires fresh
Minimal TTY and Stock GNOME QEMU acceptance before the committed state changes.

## External source inputs

`maintenance/sources.json` lists only sources currently used by the installer or package recipes:
Arch packages, GNOME, Marble, Colloid, GNOME extensions, pinned AUR inputs, Gum, the Starship preset
and license/source provenance. Offline binding is mandatory:

```bash
python3 maintenance/check-sources.py
```

A scheduled or manual advisory run may query upstream services:

```bash
python3 maintenance/check-sources.py --network --report "$ARTIFACT_DIR/source-advisory.json"
```

Findings are informational. The workflow creates or updates one advisory issue and performs no
commit, merge, release, signing, pin update, key rotation or remediation pull request.

## A+B reproducibility

Two independent clean Arch builds are compared monthly as advisory evidence:

```bash
repository/compare-package-builds.sh "$ARTIFACT_DIR/build-a" "$ARTIFACT_DIR/build-b"
```

A mismatch updates the same advisory issue but does not block the normal release path. The required
release build is one clean canonical Arch build.
