# Advisory maintenance

Maintenance detects drift; it does not change source, accepted hashes, pins, keys or releases.

## Public signing key expiry

```bash
python3 maintenance/check-key-lifetime.py
```

The existing maintenance workflow checks the tracked public certificate daily, as well as on a
manual run. It updates the same advisory issue without erasing unresolved monthly findings.
Warnings begin 210 days before expiry; manual renewal is due at 180 days, with urgent/critical
warnings at 90/30 days. Repeated unchanged warnings do not generate issue updates. Production
signing still requires at least 180 days remaining.

The current signing subkey expires on **2027-08-24 at 11:42:46 UTC**; the renewal cycle begins
**2027-02-25**. These dates are read from the public certificate, not silently updated trust pins.
GitHub never renews a key or handles private material. Follow the
[manual renewal procedure](trust-model.md#expiry-renewal-and-installed-systems).

GitHub scheduled runs may be delayed and public repositories with no activity can have schedules
disabled. Check Actions periodically and keep a separate maintainer calendar reminder; a workflow
is not a guaranteed real-time alarm. See [GitHub schedule limitations](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

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

Arch versions recorded as full package versions retain epoch and pkgrel during comparison;
legacy pkgver-only entries compare pkgver only. A tagged upstream is checked against its exact
tag (peeled for annotated tags), not an unrelated default-branch HEAD. A configured latest-release
endpoint is checked separately, so newer releases still produce an advisory. Missing tags and
network errors remain visible; none of these checks changes the accepted inputs.

## A+B reproducibility

Two independent clean Arch builds are compared monthly as advisory evidence:

```bash
repository/compare-package-builds.sh "$ARTIFACT_DIR/build-a" "$ARTIFACT_DIR/build-b"
```

A mismatch updates the same advisory issue but does not block the normal release path. The required
release build is one clean canonical Arch build.
The daily key-only run does not rebuild packages or query every external source.

The comparison returns 0 for exact match, 1 for a verified mismatch, and 2 for verification/usage
errors. The issue distinguishes differing bytes from an unavailable comparison. No package member,
including `.BUILDINFO` or `.MTREE`, is excluded to obtain a match.

Both disposable Actions build containers use `WORK_DIR=/tmp/arch-linux-canonical-work`.
makepkg records the actual build/start directories in `.BUILDINFO`; a random directory would
otherwise cause different archives even with identical installed payloads. The directory must not
exist and must be disjoint from source and output; the builder creates and owns it exclusively,
then removes it on completion. Do not point WORK_DIR at existing data or run concurrent builds at
that same path in a shared environment. Local builds without WORK_DIR retain isolated `mktemp`
directories. Build environments can still drift independently; actual mismatches remain advisory.
