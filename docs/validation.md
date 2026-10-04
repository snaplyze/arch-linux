# Validation and evidence

Validation is layered and tree-bound. No old report or status document is evidence for the current
source candidate.

## Verified release 1.0.6 — 2026-10-04

[Configured run37214392242](https://github.com/snaplyze/arch-linux/actions/runs/37214392242)
produced [immutable release1.0.6](https://github.com/snaplyze/arch-linux/releases/tag/1.0.6),
Release ID403102824, published2026-10-04T16:22:59Z with exactly18 assets after verified Pages deployment.
[PR59](https://github.com/snaplyze/arch-linux/pull/59) passed required Source checks before squash;
this same checkout returned to main by fast-forward. The candidate and originmain share exact
mode-and-byte source identity; the version-only release child is bound separately.

| Binding | Exact value |
| --- | --- |
| Pre-merge accepted candidate | `a9e417304e9883aa354f5ed2cda6a9ead0438eec` |
| Origin main | `696b420bc93415d44bb3ab64b35df7539cbbe87b` |
| Origin/candidate tree | `2d3e7f1abf454c462586cb5450ae1c79d3ccee0a` |
| Origin/candidate canonical SHA-256 | `6d8da82f8008f9d8d002f8a9bd0bb3c60b7db6530eb4894657ad0fcfd38d6250` |
| Release child | `7af2209be497a0a5f0e314cd8cc20f691e52b064` |
| Release tree | `83bd2d9de7d4883b08fbb81c78cce8fe0d36374d` |
| Release canonical SHA-256 | `f6b6517655429ca06afb1cd241d971fe4ccb02352a231020145853ed8b7185ff` |
| Annotated tag object | `54d1208417e872bb08b5b9128752d36030205145` |
| Accepted October ISO SHA-256 | `684ded26c63240ff4a41e8c25ee84ea6da233f557364821f13d12c2b0a9059a5` |
| Repository snapshot SHA-256 | `25a129f7fa0f91d9ec85d0418ba938dd62e7fea0052838f76b89b3292a795496` |
| Build metadata SHA-256 | `b8cbf4689bac5ad75403a5fc2a1f17e8415a706b5c076d84bb2511e0dfecefec` |
| Unsigned manifest SHA-256 | `b5115ae0838e9c5f01a7fb14a5f32843e2c213ba6ebb31674ea2522f10c05639` |
| Harness SHA-256 | `3409f1b2f1f1bd8c689eccafa1d5f27de009b0a6e0dc74c4086aa0fe28c2e2fb` |

`EXECUTED_PASS`: clean `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh` (source35/native0;
includes full namespace10/signer14+18/deferrednone), canonical unprivileged six-package build and
separate fresh container verification, and these five actual release-host commands in a disposable
installed real-root VM, each native0 with its mandatory marker:

```bash
bash tests/repository-checks.sh
bash tests/repository-checks.sh --require-full-namespace
/usr/bin/env -i HOME=/root LANG=C LC_ALL=C PATH=/usr/bin:/usr/sbin \
  /usr/bin/bash --noprofile --norc tests/publication-root-check.sh </dev/null
bash tests/keyring-rotation-checks.sh
env ARCH_LINUX_PRIVILEGED_ACCEPTANCE=true bash tests/keyring-rotation-checks.sh
```

Source35 log SHA-256 `051ee2f2183995c1f493e2e9e70fc40ade36b01d0a7aae9ea36df9ef7fa531cd`;
actual root gate log SHA-256 `f7ae55b1d7f844793827efd03be39c024dfa178df892081e06550f60a85d9456`.
Before/after source identities match; real UID map, quiescent captured PIDs and healthy images
were independently checked before exact-owned cleanup. These fixtures prove pre-merge boundaries,
not production signing. The later configured child build/readback/signing is a separate successful
execution, with actual bundle graph checked in memory without a development checkout or Git import.

| Actual new-child staged scenario | Status | Assertions |
| --- | --- | --- |
| `marble-gnome-btrfs-luks2-plymouth-systemdboot` | EXECUTED_PASS | 26 |
| `marble-gnome-btrfs-luks2-plymouth-systemdboot-stock-gdm` | EXECUTED_PASS | 17 |
| `minimal-dualboot-ext4-systemdboot` | EXECUTED_PASS | 17 |
| `minimal-ext4-systemdboot` | EXECUTED_PASS | 14 |
| `stock-gnome-btrfs-grub` | EXECUTED_PASS | 23 |
| `stock-gnome-btrfs-luks2-plymouth-grub` | EXECUTED_PASS | 22 |
| `stock-gnome-btrfs-luks2-plymouth-systemdboot` | EXECUTED_PASS | 21 |
| `stock-gnome-btrfs-systemdboot` | EXECUTED_PASS | 21 |
| `stock-gnome-ext4-systemdboot` | EXECUTED_PASS | 21 |

All nine results bind the same exact child, ISO, harness, signed snapshot and build/unsigned inputs.
Real password login, Wayland, lock/unlock, update/reboot, integrity, no failed units, clean poweroff
and image health passed where required.
Live installer cancellation, busy-resource cleanup and crash-path VM injection remain NOT_TESTED.
RECOVERY-01 accepts the specified source actual-handler failure/cancellation and concurrent
retention regressions; the nine successful scenarios do not establish those additional live paths. Plain Stock Btrfs/GRUB's23 assertions include real
read-only filesystem snapshot boot and normal-root return/owned cleanup; encrypted GRUB22 is
normal encrypted installation coverage. Marble26 additionally covers honest helper failure and
explicit GDM deactivation. Native result bytes and process chronology were independently checked.

`EXECUTED_PASS`: exact14 Phase-A, original14 byte-identical in finalized18, new acceptance/evidence
signatures, full production evidence validation, native core result hashes and `deferred=[]`.
The signed [acceptance JSON](https://github.com/snaplyze/arch-linux/releases/download/1.0.6/arch-linux-acceptance-1.0.6.json)
binds the full Phase-A map; evidence is1,948,353 bytes, below500MiB. Exact published asset map:

| Asset | Bytes | SHA-256 |
| --- | --- | --- |
| `BUILD-METADATA.json` | 737 | `b8cbf4689bac5ad75403a5fc2a1f17e8415a706b5c076d84bb2511e0dfecefec` |
| `RELEASE-SHA256SUMS` | 1107 | `d0c99ad072dc00ad61a639868e555fe2922671c32d0d8a049153e8d5146fc1cc` |
| `RELEASE-SHA256SUMS.sig` | 118 | `dc40d8940a3708339c2f018faa784e43dbf2054f6f0216acb36de77e6f14e42b` |
| `UNSIGNED-SHA256SUMS` | 1326 | `b5115ae0838e9c5f01a7fb14a5f32843e2c213ba6ebb31674ea2522f10c05639` |
| `arch-linux-acceptance-1.0.6.json` | 5283 | `13e6d8fa2139664fb7bab45042da0b156961f748e96fd656fc9d3c5bb5b23228` |
| `arch-linux-acceptance-1.0.6.json.sig` | 119 | `b159941b5d3b945c2799a2dec4efb304ab4704461526b84272a00b4bc0f10a1b` |
| `arch-linux-acceptance-evidence-1.0.6.tar.zst` | 1948353 | `c1d2a282d13d78eb95eff0ebe77544ee232b4214f6f81cd32fe1a20969db47a1` |
| `arch-linux-acceptance-evidence-1.0.6.tar.zst.sig` | 119 | `3b03534ec13401ab21c398c36488b6646c3b54b5ece42760e7227cae25e31780` |
| `arch-linux-installer.sh` | 402255 | `ebb90209b6d407f8bb54091ef4112267852269bf5744af9c54df8a8308dff55a` |
| `arch-linux-installer.sh.sha256` | 90 | `a3ef1368b540a44b802fc041c128c201a91815d647550841d96a0eea534ac776` |
| `arch-linux-installer.sh.sig` | 119 | `f98ad9d66e69ddaf36d57e0a3eb519bb16507c6079cfe92fd41adc7a622b0d0c` |
| `arch-linux-repository-1.0.6.tar.zst` | 5732653 | `25a129f7fa0f91d9ec85d0418ba938dd62e7fea0052838f76b89b3292a795496` |
| `arch-linux-repository-1.0.6.tar.zst.sha256` | 102 | `b357b8e150c74db7872d12309562ea2986686b0780545b444bf668c7f5361f8f` |
| `arch-linux-repository-1.0.6.tar.zst.sig` | 119 | `bd8b72494b61ba462a37de3af0e24d71c956f99335660b3226c0b9338643caa8` |
| `arch-linux.gpg` | 568 | `8959dfd96fd94349d505f18a6d3ef0a3bfcd9fad53291343388f787f9dbb9c6f` |
| `install.sh` | 28213 | `ee9f9c085acf6c8d2519fb8d76003da101740052afe5bf2a16bbc8957506f663` |
| `primary-fingerprint` | 41 | `7e12b5e2a2ce9ed2881e06d80054a969465eea72f917282f25f27ae02cf66824` |
| `signing-subkey-fingerprint` | 41 | `471e476b51923eb1afe73609a7ef4aef3fbc1e1c2b09ba3f77e9f1f349643b69` |

`EXECUTED_PASS`: unauthenticated HTTPS Release18 byte equality to accepted finalized18 and
annotated tag→child/run binding; all25 Pages files (23 named objects plus manifest/signature)
match the independently safe-extracted signed snapshot. Public API requires immutable=true and
exact canonical asset sizes/digests; downloads require exact size, EOF and SHA-256 under a30m
outer process deadline. Root and independent read-only checks accepted actual bytes.

Proof receipts: source graph `f719cf2597cb02edd34b7dbe560cb06891896dc5b89d0cd56ac29a702a8e2579`,
Phase-A `7838f402db5be938d7649f40abb733df73bb560fbebf0a43bb3a8e51b66ec16a`,
final18 `b69d534ce6755cf9af235edb804d3e05bb05a9660b1b1570f3e95721f02227c5`,
public bytes `957a3c88f0e95d5405f6fa8bb048d195684848939c9d174e9d0c49ad3311bb67`.
They are retained with compact native evidence in the existing external evidence register;
no signing secrets, VM disks or generated package outputs enter source.

`EXECUTED_PASS`: fresh public-only Marble/GDM VM, native0 with19 assertions. The configured
workflow completed SUCCESS. Public run `marble-20261004T162511Z-cc51576a` consumes only
immutable tagged bootstrap/verified Release installer and signed public Pages. It passed actual
HMP password login and Wayland, lock/unlock, full update, reboot/second login, package integrity,
zero failed units, clean poweroff, no matching QEMU process and healthy image. The compact
public artifact11308433140 binds the same accepted child/source/ISO/harness/snapshot/build inputs;
its manifest/signature and23 repository objects match the signed archive and public byte proof.
Native result SHA-256 `13de92af4ecc355529ae734674a7966529c62209adbb7d0d066ebf523b0d25e8`;
public archive SHA-256 `a227c1c3078672beea8c66163e2add16815ce2f43253963c7d6502d437fb1f4f`.
Public19 and staged26 remain distinct: staged-only legacy/helper-failure/removal checks are
not relabeled as public execution. Optional screenshots are retained as diagnostic evidence.

Local final-document verification uses `python3 tests/docs-checks.py`, `git diff --check` and
`PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`. Working-doc source36 passed native0;
the clean document-commit command/tree/receipt is bound in the existing register.
It does not replace or relabel the release-child VM/source identities above.

Clean local documentation commit `30d4a162ed99141c4ccd2b43273a90f1fda0b756` (tree `895fb77ea77e2f66ef5bf8cbb49ba6f21572004b`, canonical SHA-256 `368587520f60e525c9ede887e08b139e77aa42597dbbfc6da2705422339c04d6`) passed `PYTHONDONTWRITEBYTECODE=1 bash tests/source-tests.sh`, source37/native0/session71065; log SHA-256 `ad9f3e402e3bcfaf772d44c3b88ec422e4eba3df6a948b91d7dcd8610ece3ccd`. This result belongs to that exact documentation tree. Later documentation edits require fresh applicable checks; the evidence register preserves each exact tree/result.
Historical predecessor failures, 1.0.5 media qualification and older release results retain their
original identities. Final documentation was initially retained in localmain commits. A subsequent
explicit owner request authorizes checked PR/main publication of these documents. Record its exact
outcome in the same evidence register after publication. This publication requires no new installer release.

## Historical audit record

The [single registry](PLAN.md#review-findings) records the October 2 review and October 3
documentary follow-up, coverage, open findings and exact check outcomes. Documentary corrections
do not fix product defects. Fresh builds, production signing, crash/race acceptance, real account
creation and real VM installation were not executed by this follow-up; they remain NOT_TESTED
(`NOT_RUN_ENVIRONMENT` in the check-status vocabulary below).

## Public readback of release 1.0.5

October 3 execution independently downloaded all 18 immutable [1.0.5 Release assets](https://github.com/snaplyze/arch-linux/releases/tag/1.0.5),
checked their API size/SHA-256 map, exact-12 `RELEASE-SHA256SUMS` coverage and all five
release detached signatures against the committed public certificate and exact signing subkey.
Public trust files match the committed bytes. The Pages manifest and signature match the signed
repository archive bytes; all 23 named repository objects match size/hash, and the manifest,
two databases and six packages pass detached signature verification. The semantic database
checker additionally accepted the real published database/package pair.

| Binding | Value |
| --- | --- |
| Release commit | `61add3e0b2c20adbbdd425494eae02ddec0a3bac` |
| Release tree | `b5ca51e80277d93541d00a305490ac818d629a33` |
| Canonical source SHA-256 in signed acceptance | `02816596c2e2e72cddb31b357723660685e4c77fce929c76b04f5e21dee18d37` |
| Repository archive SHA-256 | `79413af54fca28fc1afef9fbfe6dea24875470d1a3cd65a6c459eb85bde26474` |
| Build metadata SHA-256 | `c6d7a812737b41e52e8ea3cb59613ac2ceb0e4a0e601d44f6de99820661972da` |
| Unsigned manifest SHA-256 | `97a821f50df2ab7a523107e0b9f7f956fcce6cc02189437d758c4c429bc6deae` |

Historical status: `EXECUTED_PASS` for public byte/signature readback. At that readback README commands pinned 1.0.5.
Its signed acceptance still describes the three historical September ISO runs; it is not an
October installation or corrected-candidate PASS. Subsequent corrected-release execution is recorded above and in [the registry](PLAN.md#execution-registry). The verified 1.0.4 evidence below
keeps its original identity and outcomes.

## Verified release 1.0.4

[Release 1.0.4](https://github.com/snaplyze/arch-linux/releases/tag/1.0.4) was published on
2026-09-17 with `immutable: true` and exactly 18 assets. Its annotated tag resolves to commit
`c4c46588b8eab987c3c29e6548b81bd2f6b4217f`, tree
`b973c979e781e06af30fb18f0855b9724c941e0c`. The reviewed origin main commit is
`e4e68bb58ef3a61c2de9938223a4fd214d2f6e76`. These identities describe that release, not later
changes to `main`.

The [Release workflow](https://github.com/snaplyze/arch-linux/actions/runs/35164378553)
completed successfully. Its build, independent artifact readback, signing-boundary checks, staged
VM matrix, finalization, annotated tag, Pages deployment and immutable publication passed.

| Executed scenario | Result | Functional assertions |
| --- | --- | --- |
| Minimal TTY / ext4 / systemd-boot | EXECUTED_PASS | 14 |
| Stock GNOME / Btrfs / LUKS2 / GRUB | EXECUTED_PASS | 22 |
| Marble / Btrfs / LUKS2 / systemd-boot / Marble GDM | EXECUTED_PASS | 24 |
| Public-only Marble installation from Release and Pages | EXECUTED_PASS | 19 |

The signed [acceptance JSON](https://github.com/snaplyze/arch-linux/releases/download/1.0.4/arch-linux-acceptance-1.0.4.json)
and [evidence archive](https://github.com/snaplyze/arch-linux/releases/download/1.0.4/arch-linux-acceptance-evidence-1.0.4.tar.zst)
contain the three staged results and their exact input bindings. Both have detached signatures in
the Release. The final public VM result is a separate workflow artifact; it does not modify the
already published acceptance JSON. Public attempt 3 passed; the earlier HTTP download failure and
connection reset remain failed attempts, not relabelled successes.

The staged Marble run includes legacy GTK3-package replacement, fresh-user activation and startup
of Nautilus, Ptyxis, Settings and Boxes in both color-scheme states. Startup checks and diagnostic
captures do not establish exhaustive visual compatibility. No new claim about every storage,
bootloader, dual-boot or physical-hardware combination follows from this three-scenario release.

## Source evidence

Contains exact source identity and the commands/statuses for syntax, version, bootstrap, static,
function, Marble, package metadata, documentation, portability, secret, agent, maintenance,
repository fixture and ShellCheck tests. It must not include generated package or VM outputs.

## Build evidence

Contains the clean Arch environment identity, canonical unsigned package closure,
`UNSIGNED-SHA256SUMS`, package metadata and verifier result. Monthly A+B comparison is advisory and
is recorded separately from the required canonical release build.

## QEMU evidence

Contains the accepted ISO identity, QEMU/OVMF versions, new qcow2 and independent VARS identities,
scenario configuration, installer/repository identities and a structured result. The exact release
matrix is Minimal TTY/ext4/systemd-boot, Stock GNOME/Btrfs/LUKS2/GRUB and
Marble/Btrfs/LUKS2/systemd-boot with the separate experimental Marble GDM opt-in. All three staged
runs bind the same independently verified production-signed repository archive, source commit/tree,
build-metadata hash, unsigned-manifest hash and frozen Arch ISO hash.
The staged inputs are the exact 14 Phase-A assets, whose signed checksum manifest covers exactly 12
non-self files. Finalization is allowed only after all three functional PASS results and preserves all
14 bytes while adding signed acceptance JSON and evidence archive for exact 18.

Each scenario retains a short compressed installer log, input and tool hashes, the signed repository
manifest/signature and package/database hashes, functional assertions and a structured PASS or FAIL.
A FAIL includes the failed phase and non-zero exit status. Check actual GDM password login and the
resulting Wayland session, lock/unlock, update and repeated login. Screenshots help diagnose the
result but are optional; no sampling interval or human receipt is required.

After each scenario remove its qcow2, OVMF VARS, payload, extracted repository and TLS runtime,
check that its QEMU/server processes exited, and retain `qemu-img check`. Never retain passwords,
private keys, passphrases or recovery material. Keep reports compact and separate from source;
the release evidence archive has a 500 MiB storage cap, not a frame timing or visual certification
requirement. Do not scan VM disks as if they were text logs.

## Release evidence

Contains signed repository/release-asset verification, immutable release asset identities, Pages
readback and the final public VM result. It is created only after the corresponding operations and
cannot retroactively change source/build/QEMU results. For the generated release child, provenance
also binds the exact successful origin main commit/tree and the deterministic transform record.
The acceptance JSON binds the commit/tree/canonical source SHA-256, build/unsigned/snapshot hashes,
the exact Phase-A name/hash/size map and aggregate, its manifest hash, three PASS verdicts,
evidence no larger than 500 MiB and `deferred=[]`.

The final public Marble/GDM VM carries no local product bytes: it downloads the immutable tagged bootstrap, verifies the Release installer and
public key, executes only that verified installer, and obtains project packages and databases from
the exact public Pages URL under `PackageRequired DatabaseRequired TrustedOnly`. Public readback
verifies signed `RELEASE-SHA256SUMS`, the exact archive digest and signature, byte equality between
the archive and Pages manifests/signatures, schema-2 source/build identity, all 23 Pages object
hashes/sizes, and all package/canonical-database signatures. Merely echoing an expected archive hash
or validating an unbound Pages manifest is not public readback evidence.

## Status discipline

Use exactly one status per check: `EXECUTED_PASS`, `EXECUTED_FAIL`, `REVIEWED_ONLY`,
`NOT_RUN_ENVIRONMENT` or `NOT_APPLICABLE`. Record exact commands for executed tests. Absence of a
required environment is not a PASS.
